"use server";

import { refresh } from "next/cache";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { isKokoroVoice, type KokoroVoice } from "@/lib/account-voice";
import type { ActionResult } from "@/lib/action-result";
import { findTemplate, readParts, type DashboardPart } from "@/lib/dashboard-sources";
import * as data from "@/lib/data";
import { DataError } from "@/lib/errors";
import { googleReturnTo } from "@/lib/google-calendars";
import { isCompleteCode, sanitizeCode } from "@/lib/pairing";
import { knownTimeZone } from "@/lib/timezones";
import type { DisplaySettings } from "@/lib/types";
import { AGENT_KINDS, AGENT_SCOPES, ASSISTANT_PROVIDERS, type AgentKind, type AgentScope, type AssistantProvider, type SettingsPatch } from "@/lib/types";

// Mutations behind the console's forms. Each one re-checks that the caller is
// a platform admin (server actions are public endpoints), validates its input,
// then goes through lib/data, where the RPC or edge function checks again and
// writes the audit log.

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const COLOR = /^#[0-9a-f]{6}$/i;
const SYMBOL = /^[A-Z0-9.^=:-]{1,16}$/;
const METRIC_KEY = /^[a-z0-9][a-z0-9._-]{0,63}$/;

const text = (fd: FormData, name: string, max = 500) => {
  const v = fd.get(name);
  return typeof v === "string" ? v.trim().slice(0, max) : "";
};
const uuid = (fd: FormData, name: string) => {
  const v = text(fd, name, 64);
  if (!UUID.test(v)) throw new DataError("That link is out of date. Reload the page and try again.");
  return v.toLowerCase();
};
const int = (fd: FormData, name: string, min: number, max: number, label: string) => {
  const raw = text(fd, name, 12);
  const n = Number(raw);
  if (raw === "" || !Number.isInteger(n) || n < min || n > max) {
    throw new DataError(`${label} must be a whole number from ${min} to ${max}.`);
  }
  return n;
};
const kind = (fd: FormData, name: string): AgentKind => {
  const v = text(fd, name, 16);
  if (!AGENT_KINDS.includes(v as AgentKind)) throw new DataError("Kind must be grok, stocks, news or other.");
  return v as AgentKind;
};
// Checked boxes named `scope` (one per granted permission).
const scopes = (fd: FormData): AgentScope[] =>
  [...new Set(fd.getAll("scope").map(String))].filter((v): v is AgentScope => AGENT_SCOPES.includes(v as AgentScope));

const color = (fd: FormData, name: string): string | null => {
  const v = text(fd, name, 16);
  if (!v) return null;
  if (!COLOR.test(v)) throw new DataError("Color must be a hex color like #4F7CF7.");
  return v.toUpperCase();
};

// Runs a mutation and turns failures into a message for the form. The admin
// check sits outside the try: its redirect must not be swallowed.
async function mutate(fn: () => Promise<ActionResult | void>, { rerender = true } = {}): Promise<ActionResult> {
  await data.requireAdmin();
  try {
    const result = await fn();
    if (rerender) refresh();
    return result ?? { ok: true };
  } catch (err) {
    if (err instanceof DataError) return { ok: false, error: sentence(err.message) };
    console.error("admin action failed:", err);
    return { ok: false, error: "Something went wrong. Try again." };
  }
}

const sentence = (s: string) => {
  const t = s.trim();
  return t ? t[0].toUpperCase() + t.slice(1) + (/[.!?]$/.test(t) ? "" : ".") : "Something went wrong.";
};

// ───────────────────────────── Agents ─────────────────────────────

export async function createAgentAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const name = text(fd, "name", 80);
    if (!name) throw new DataError("Give the agent a name.");
    const agent = await data.createAgent(name, kind(fd, "kind"), color(fd, "color"));
    const granted = scopes(fd);
    if (granted.length) await data.setAgentScopes(agent.id, granted);
    // The key rides back to the form and nowhere else.
    return { ok: true, message: `${name} created.`, key: agent.key, slug: agent.slug, agentId: agent.id };
  });
}

export async function rotateAgentKeyAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const key = await data.rotateAgentKey(uuid(fd, "agent_id"));
    return { ok: true, message: "Key rotated. The old key stopped working.", key };
  });
}

export async function updateAgentAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const id = uuid(fd, "agent_id");
    const name = text(fd, "name", 80);
    if (!name) throw new DataError("Give the agent a name.");
    const c = color(fd, "color");
    await data.updateAgent(id, { name, kind: kind(fd, "kind"), ...(c ? { color: c } : {}) });
    if (fd.get("scopes_present")) await data.setAgentScopes(id, scopes(fd));
    return { ok: true, message: "Agent updated." };
  });
}

export async function revokeAgentAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    await data.revokeAgent(uuid(fd, "agent_id"));
    return { ok: true, message: "Agent revoked. Its pushes are refused until a new key is made." };
  });
}

export async function deleteAgentAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const id = uuid(fd, "agent_id");
    const expected = text(fd, "expected", 80);
    if (!expected || text(fd, "confirm", 81) !== expected) {
      throw new DataError(`Type the agent's name, ${expected || "as shown"}, exactly to confirm.`);
    }
    await data.deleteAgent(id);
    return { ok: true, message: `${expected} deleted, with everything it pushed.` };
  });
}

// ───────────────────────────── Feed ─────────────────────────────

export async function deleteBriefAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    await data.deleteBrief(uuid(fd, "brief_id"));
    return { ok: true, message: "Brief deleted." };
  });
}

export async function setSymbolAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const symbol = text(fd, "symbol", 16).toUpperCase();
    if (!SYMBOL.test(symbol)) throw new DataError("That symbol isn't usable.");
    const hidden = fd.get("hidden") === "on";
    const sortOrder = int(fd, "sort_order", -100_000, 100_000, "Order");
    await data.setSymbol(symbol, { hidden, sort_order: sortOrder });
    return { ok: true, message: `${symbol} saved.` };
  });
}

export async function deleteSymbolAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const symbol = text(fd, "symbol", 16).toUpperCase();
    if (!SYMBOL.test(symbol)) throw new DataError("That symbol isn't usable.");
    await data.deleteSymbol(symbol);
    return { ok: true, message: `${symbol} and its quotes deleted.` };
  });
}

export async function deleteNewsReportAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  let deleted = false;
  const result = await mutate(
    async () => {
      await data.deleteNewsReport(uuid(fd, "report_id"));
      deleted = true;
    },
    { rerender: fd.get("stay") === "1" },
  );
  // From the report's own page there is nothing left to show.
  if (result?.ok && deleted && fd.get("stay") !== "1") redirect("/feed?tab=news&deleted=1");
  return result?.ok ? { ok: true, message: "Report deleted." } : result;
}

// ───────────────────── Productivity feeds ─────────────────────

export async function deleteProjectAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  let deleted = false;
  const result = await mutate(
    async () => {
      await data.deleteProject(uuid(fd, "project_id"));
      deleted = true;
    },
    { rerender: fd.get("stay") === "1" },
  );
  // From the project's own page there is nothing left to show.
  if (result?.ok && deleted && fd.get("stay") !== "1") redirect("/feed?tab=projects&deleted=project");
  return result?.ok ? { ok: true, message: "Project deleted." } : result;
}

const metricKey = (fd: FormData) => {
  const key = text(fd, "metric", 64).toLowerCase();
  if (!METRIC_KEY.test(key)) throw new DataError("That metric key isn't usable.");
  return key;
};

export async function setMetricAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const key = metricKey(fd);
    const label = text(fd, "label", 80);
    const group = text(fd, "group_name", 80);
    await data.setMetric(key, {
      hidden: fd.get("hidden") === "on",
      sort_order: int(fd, "sort_order", -100_000, 100_000, "Order"),
      // Blank keeps the current label or group (the RPC treats null as "keep").
      ...(label ? { label } : {}),
      ...(group ? { group_name: group } : {}),
    });
    return { ok: true, message: `${key} saved.` };
  });
}

export async function deleteMetricAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const key = metricKey(fd);
    await data.deleteMetric(key);
    return { ok: true, message: `${key} and its history deleted.` };
  });
}

export async function setDashboardAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    await data.setDashboard(uuid(fd, "dashboard_id"), {
      hidden: fd.get("hidden") === "on",
      sort_order: int(fd, "sort_order", -100_000, 100_000, "Order"),
    });
    return { ok: true, message: "Dashboard saved." };
  });
}

export async function deleteDashboardAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  let deleted = false;
  const result = await mutate(
    async () => {
      await data.deleteDashboard(uuid(fd, "dashboard_id"));
      deleted = true;
    },
    { rerender: fd.get("stay") === "1" },
  );
  if (result?.ok && deleted && fd.get("stay") !== "1") redirect("/feed?tab=dashboards&deleted=dashboard");
  return result?.ok ? { ok: true, message: "Dashboard deleted." } : result;
}

// A made board's recipe, as the builder sends it: the parts as JSON.
const dashboardParts = (fd: FormData): DashboardPart[] => {
  let raw: unknown;
  try {
    raw = JSON.parse(text(fd, "sources", 60_000) || "[]");
  } catch {
    throw new DataError("The dashboard's parts didn't come through. Reload the page and try again.");
  }
  const parts = readParts(raw);
  if (parts.length === 0) throw new DataError("Add at least one part, a note if nothing else.");
  return parts;
};

// Makes a dashboard from the builder, or saves a made one, then opens it.
export async function saveDashboardAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  let saved: string | null = null;
  const result = await mutate(
    async () => {
      const title = text(fd, "title", 80);
      if (!title) throw new DataError("Give the dashboard a title.");
      const template = text(fd, "template", 40);
      saved = await data.saveDashboard({
        id: text(fd, "dashboard_id", 64) ? uuid(fd, "dashboard_id") : null,
        title,
        subtitle: text(fd, "subtitle", 200) || null,
        template: findTemplate(template) ? template : null,
        parts: dashboardParts(fd),
      });
    },
    { rerender: false },
  );
  if (result?.ok && saved) redirect(`/feed/dashboards/${saved}`);
  return result;
}

export type DashboardPreview = { ok: true; widgets: unknown[] } | { ok: false; error: string };

// The builder's live preview: what the parts draw right now, from the real
// feeds, without saving anything.
export async function previewDashboardAction(raw: unknown): Promise<DashboardPreview> {
  await data.requireAdmin();
  const parts = readParts(raw);
  if (parts.length === 0) return { ok: true, widgets: [] };
  try {
    return { ok: true, widgets: await data.previewDashboard(parts) };
  } catch (err) {
    if (err instanceof DataError) return { ok: false, error: sentence(err.message) };
    console.error("dashboard preview failed:", err);
    return { ok: false, error: "The preview didn't draw. Try again." };
  }
}

export async function deleteEventAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    await data.deleteEvent(uuid(fd, "event_id"));
    return { ok: true, message: "Event deleted. The agent's next push may bring it back." };
  });
}

export async function deleteCalendarAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const calendar = text(fd, "calendar", 80);
    if (!calendar) throw new DataError("Which calendar?");
    const removed = await data.deleteCalendar(uuid(fd, "agent_id"), calendar);
    return { ok: true, message: `${calendar} removed (${removed} event${removed === 1 ? "" : "s"}).` };
  });
}

// ───────────────────────────── Displays ─────────────────────────────

export async function renameDeviceAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const name = text(fd, "name", 80);
    if (!name) throw new DataError("Give the display a name.");
    await data.renameDevice(uuid(fd, "device_id"), name);
    return { ok: true, message: "Display renamed." };
  });
}

export async function revokeDeviceAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const { authUserRemoved } = await data.revokeDevice(uuid(fd, "device_id"));
    return {
      ok: true,
      message: authUserRemoved
        ? "Display revoked. It signs out within a minute and shows a pairing code."
        : "Display revoked. Its sign-in could not be removed yet; check the admin function's logs.",
    };
  });
}

export async function claimDeviceAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const code = sanitizeCode(fd.get("code"));
    if (!isCompleteCode(code)) throw new DataError("Enter the 6 digits shown on the display.");
    const name = text(fd, "name", 80) || null;
    const { deviceId } = await data.claimDevice(code, name);
    return { ok: true, message: "Display paired.", deviceId };
  });
}

// ───────────────────────────── Settings ─────────────────────────────

export async function updateSettingsAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const displayName = text(fd, "display_name", 80);
    if (!displayName) throw new DataError("Give the display a name.");
    const timezone = text(fd, "timezone", 64);
    if (!timezone || !knownTimeZone(timezone)) throw new DataError("That time zone isn't known. Use an IANA name like America/Chicago.");
    const provider = text(fd, "assistant_provider", 16);
    if (!ASSISTANT_PROVIDERS.includes(provider as AssistantProvider)) throw new DataError("The assistant must be Claude or Grok.");
    const next = {
      display_name: displayName,
      timezone,
      briefs_keep_days: int(fd, "briefs_keep_days", 1, 3650, "Briefs retention"),
      quotes_keep_days: int(fd, "quotes_keep_days", 1, 3650, "Quotes retention"),
      news_keep_reports: int(fd, "news_keep_reports", 1, 1000, "Reports kept"),
      assistant_provider: provider as AssistantProvider,
      metrics_keep_days: int(fd, "metrics_keep_days", 1, 3650, "Metrics retention"),
      events_keep_days: int(fd, "events_keep_days", 1, 3650, "Events retention"),
    };
    // Send only what this admin changed (the form carries the values it was
    // opened with), so saving a form opened before another change can't
    // quietly undo it. Null leaves a setting as it is (admin_update_settings).
    const patch: SettingsPatch = {};
    for (const key of Object.keys(next) as (keyof typeof next)[]) {
      if (String(next[key]) !== text(fd, `was_${key}`, 80)) Object.assign(patch, { [key]: next[key] });
    }
    if (Object.keys(patch).length === 0) return { ok: true, message: "Nothing changed." };
    await data.updateSettings(patch);
    return { ok: true, message: "Settings saved." };
  });
}

// ───────────────────────────── Session ─────────────────────────────

export async function signOutAction(): Promise<void> {
  try {
    await data.signOut();
  } catch (err) {
    if (!(err instanceof DataError)) throw err; // not configured: nobody is signed in
  }
  redirect("/login?signed_out=1");
}

export async function setAgentScopesAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const saved = await data.setAgentScopes(uuid(fd, "agent_id"), scopes(fd));
    return { ok: true, message: saved.length ? `Permissions saved: ${saved.join(", ")}.` : "Permissions removed." };
  });
}

// For the setup panel's "waiting for the first push": when the agent was last
// heard from, or null. Read-only, so no rerender.
export async function agentLastSeenAction(agentId: string): Promise<string | null> {
  await data.requireAdmin();
  if (!UUID.test(agentId)) return null;
  const agents = await data.listAgents();
  return agents.find((a) => a.id === agentId.toLowerCase())?.last_seen_at ?? null;
}

// ───────────────────────────── Memory ─────────────────────────────

export async function saveMemoryAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const id = text(fd, "memory_id", 64);
    const body = text(fd, "text", 2000);
    const pinnedRaw = text(fd, "pinned", 8);
    const agentRaw = text(fd, "agent_id", 64);
    if (!id && !body) throw new DataError("Write the note first.");
    await data.saveMemory({
      id: id ? uuid(fd, "memory_id") : null,
      text: body || null,
      pinned: pinnedRaw === "" ? null : pinnedRaw === "true",
      agentId: agentRaw ? uuid(fd, "agent_id") : null,
    });
    return { ok: true, message: id ? "Note saved." : "Note added." };
  });
}

export async function deleteMemoryAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    await data.deleteMemory(uuid(fd, "memory_id"));
    return { ok: true, message: "Note deleted." };
  });
}

// ───────────────────────────── Calendar subscriptions ─────────────────────────────

export async function addCalendarSourceAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const name = text(fd, "name", 80);
    const link = text(fd, "url", 2000);
    if (!name) throw new DataError("Give the calendar a name.");
    if (!link) throw new DataError("Paste the calendar's iCal link.");
    const id = await data.addCalendarSource(name, link, color(fd, "color"));
    // Read it right away so the events show up now, not in 15 minutes.
    const result: { count?: number; error?: string } = await data.syncCalendarSource(id).catch(() => ({ error: "it will be read in the next 15 minutes" }));
    return {
      ok: true,
      message: result.error ? `${name} added. ${sentence(result.error)}` : `${name} added with ${result.count ?? 0} events.`,
    };
  });
}

export async function updateCalendarSourceAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const id = uuid(fd, "source_id");
    const enabled = text(fd, "enabled", 8);
    await data.updateCalendarSource(id, {
      ...(text(fd, "name", 80) ? { name: text(fd, "name", 80) } : {}),
      ...(color(fd, "color") ? { color: color(fd, "color") as string } : {}),
      ...(enabled ? { enabled: enabled === "true" } : {}),
    });
    return { ok: true, message: enabled === "false" ? "Paused." : enabled === "true" ? "Resumed." : "Calendar saved." };
  });
}

export async function deleteCalendarSourceAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    await data.deleteCalendarSource(uuid(fd, "source_id"));
    return { ok: true, message: "Calendar removed, with its events." };
  });
}

export async function syncCalendarSourceAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const result = await data.syncCalendarSource(uuid(fd, "source_id"));
    if (result.error) throw new DataError(result.error);
    return { ok: true, message: `Synced: ${result.count ?? 0} events.` };
  });
}

// ───────────────────────────── Google accounts ─────────────────────────────

// Sends the admin to Google. A plain form action that ends in a redirect, so
// it stays out of mutate(), whose try would swallow the redirect; a failure
// comes back to the page as ?google_error=, the way the sign-in's own
// failures do.
export async function connectGoogleAction(fd: FormData): Promise<void> {
  await data.requireAdmin();
  const h = await headers();
  const host = h.get("host");
  const origin = h.get("origin") ?? (host ? `${h.get("x-forwarded-proto") ?? "https"}://${host}` : null);
  const returnTo = googleReturnTo(origin);
  let url: string | null = null;
  let problem = "Something went wrong. Try again.";
  if (!returnTo) {
    problem = "Couldn't tell this console's own address, so Google would have nowhere to send you back.";
  } else {
    try {
      url = await data.beginGoogleConnect(returnTo, text(fd, "email", 320) || null);
    } catch (err) {
      if (err instanceof DataError) problem = sentence(err.message);
      else console.error("google connect failed:", err);
    }
  }
  redirect(url ?? `/calendars?google_error=${encodeURIComponent(problem)}`);
}

// A calendar's switch: on adds it (and reads it right away), off removes it
// with its events.
export async function toggleGoogleCalendarAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const name = text(fd, "name", 80) || "Google";
    if (text(fd, "on", 8) === "true") {
      const calendarId = text(fd, "calendar_id", 300);
      if (!calendarId) throw new DataError("Which calendar?");
      const id = await data.addGoogleCalendar(uuid(fd, "account_id"), calendarId, name, color(fd, "color"));
      const result: { count?: number; error?: string } = await data.syncCalendarSource(id).catch(() => ({ error: "it will be read in the next 15 minutes" }));
      return {
        ok: true,
        message: result.error ? `${name} added. ${sentence(result.error)}` : `${name} added with ${result.count ?? 0} events.`,
      };
    }
    await data.deleteCalendarSource(uuid(fd, "source_id"));
    return { ok: true, message: `${name} removed, with its events.` };
  });
}

export async function disconnectGoogleAccountAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const email = await data.disconnectGoogleAccount(uuid(fd, "account_id"));
    return { ok: true, message: `${email} disconnected. Its calendars left the display.` };
  });
}

// ───────────────────────────── Display settings ─────────────────────────────

const SAVERS = ["ambient", "clock", "headlines"] as const;
const HOME_LAYOUTS = ["today", "bento", "assistant"] as const;
const BACKDROPS = ["mesh", "arc", "ribbons", "dawn", "silk", "pillars"] as const;
const WEATHERS = ["off", "season", "snow", "petals", "fireflies", "leaves"] as const;
const WAKEWORDS = ["hey_mcfly", "hey_jarvis", "alexa", "hey_mycroft", "hey_rhasspy"] as const;
const KOKORO_VOICES = ["af_heart", "af_bella", "am_michael", "am_fenrir"] as const;

// "HH:MM" → minutes after midnight.
const minuteOfDay = (fd: FormData, name: string, label: string) => {
  const m = /^(\d{1,2}):(\d{2})$/.exec(text(fd, name, 5));
  if (!m || Number(m[1]) > 23 || Number(m[2]) > 59) throw new DataError(`${label} must be a time like 22:00.`);
  return Number(m[1]) * 60 + Number(m[2]);
};

export async function updateDeviceSettingsAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const id = uuid(fd, "device_id");
    const saver = text(fd, "screensaver", 16);
    const backdrop = text(fd, "backdrop", 16) || "mesh";
    const weather = text(fd, "weather", 16) || "off";
    const homeLayout = text(fd, "homeLayout", 16) || "today";
    const provider = text(fd, "assistantProvider", 16);
    const wake = text(fd, "wakewordModel", 16);
    const speed = Number(text(fd, "voiceSpeed", 8) || "1");
    if (!SAVERS.includes(saver as (typeof SAVERS)[number])) throw new DataError("Pick a screen saver.");
    if (!BACKDROPS.includes(backdrop as (typeof BACKDROPS)[number])) throw new DataError("Pick a backdrop.");
    if (!WEATHERS.includes(weather as (typeof WEATHERS)[number])) throw new DataError("Pick the weather.");
    if (!HOME_LAYOUTS.includes(homeLayout as (typeof HOME_LAYOUTS)[number])) throw new DataError("Pick a home layout.");
    if (!["", "claude", "grok"].includes(provider)) throw new DataError("Pick who answers.");
    if (!WAKEWORDS.includes(wake as (typeof WAKEWORDS)[number])) throw new DataError("Pick a wake word.");
    const voice = text(fd, "voice", 16);
    if (!KOKORO_VOICES.includes(voice as (typeof KOKORO_VOICES)[number])) throw new DataError("Pick a voice.");
    if (!(speed >= 0.5 && speed <= 2)) throw new DataError("Voice speed must be 0.5 to 2.");
    const on = (name: string) => fd.get(name) === "true";
    const patch: DisplaySettings = {
      screensaver: saver as DisplaySettings["screensaver"],
      backdrop: backdrop as DisplaySettings["backdrop"],
      weather: weather as DisplaySettings["weather"],
      homeLayout: homeLayout as DisplaySettings["homeLayout"],
      darkMode: on("darkMode"),
      animatedTiles: on("animatedTiles"),
      idleSeconds: int(fd, "idleSeconds", 30, 3600, "Screen saver after"),
      offAfterSeconds: int(fd, "offAfterSeconds", 0, 86400, "Turn off after"),
      offAtNight: on("offAtNight"),
      bedtime: minuteOfDay(fd, "bedtime", "Bedtime"),
      wakeTime: minuteOfDay(fd, "wakeTime", "Wake time"),
      assistantProvider: provider as DisplaySettings["assistantProvider"],
      speakReplies: on("speakReplies"),
      wakeword: on("wakeword"),
      wakewordModel: wake as DisplaySettings["wakewordModel"],
      voice: voice as DisplaySettings["voice"],
      voiceSpeed: Math.round(speed * 100) / 100,
    };
    const before = (await data.listDevices()).find((d) => d.id === id)?.settings.voice;
    await data.updateDeviceSettings(id, patch);
    // The voice is the account's: a new one goes to every display, and the
    // web and the app follow it (lib/account-voice.ts).
    if (patch.voice && patch.voice !== before) await data.setAccountVoice(patch.voice);
    return { ok: true, message: "Saved. The display picks it up within a minute." };
  });
}

// The account's voice, for the voice page and Ask (lib/account-voice.ts).
// Read-only, so no rerender.
export async function accountVoiceAction(): Promise<KokoroVoice | null> {
  await data.requireAdmin();
  try {
    return await data.getAccountVoice();
  } catch (err) {
    console.error("reading the account's voice failed:", err);
    return null; // the browser keeps speaking with what it has
  }
}

// A Kokoro voice picked on the web goes to every display; the Pi and the
// app follow it. "This device's voice" never comes here.
export async function setAccountVoiceAction(voice: string): Promise<ActionResult> {
  return mutate(
    async () => {
      if (!isKokoroVoice(voice)) throw new DataError("Pick a voice.");
      const displays = await data.setAccountVoice(voice);
      return { ok: true, message: displays ? "Every display and the app speak with it now." : "No display yet: this browser keeps it." };
    },
    { rerender: false },
  );
}

// ───────────────────────────── Grok bots ─────────────────────────────

const BOT_EVERY = [15, 30, 60, 180, 360, 720, 1440];

export async function saveBotAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const id = text(fd, "bot_id", 64);
    const name = text(fd, "name", 80);
    const prompt = text(fd, "prompt", 8000);
    const output = text(fd, "output", 8);
    const every = Number(text(fd, "every_minutes", 6));
    const at = text(fd, "at_time", 5);
    if (!name) throw new DataError("Give the bot a name.");
    if (prompt.length < 10) throw new DataError("Write what the bot should do (at least a sentence).");
    if (output !== "brief" && output !== "news") throw new DataError("Pick what it writes.");
    if (!BOT_EVERY.includes(every)) throw new DataError("Pick how often it runs.");
    const web = fd.get("web_search") === "true";
    const x = fd.get("x_search") === "true";
    await data.saveBot(id ? uuid(fd, "bot_id") : null, {
      name,
      color: color(fd, "color"),
      prompt,
      output,
      every_minutes: every,
      at_minute: at ? minuteOfDay(fd, "at_time", "Start time") : null,
      web_search: web,
      x_search: x,
      model: text(fd, "model", 60),
      scopes: scopes(fd),
    });
    return { ok: true, message: id ? `${name} saved.` : `${name} created. Use "Run now" to see its first report.` };
  });
}

export async function setBotEnabledAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const on = text(fd, "enabled", 8) === "true";
    await data.saveBot(uuid(fd, "bot_id"), { enabled: on });
    return { ok: true, message: on ? "Resumed." : "Paused." };
  });
}

export async function deleteBotAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    await data.deleteBot(uuid(fd, "bot_id"));
    return { ok: true, message: "Bot deleted, with everything it wrote." };
  });
}

export async function runBotAction(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  return mutate(async () => {
    const result = await data.runBot(uuid(fd, "bot_id"));
    if (result.error) throw new DataError(result.error);
    return { ok: true, message: `Done: "${result.title ?? "report"}" is on the display.` };
  });
}
