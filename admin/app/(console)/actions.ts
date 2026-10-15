"use server";

import { refresh } from "next/cache";
import { redirect } from "next/navigation";
import type { ActionResult } from "@/lib/action-result";
import * as data from "@/lib/data";
import { DataError } from "@/lib/errors";
import { isCompleteCode, sanitizeCode } from "@/lib/pairing";
import { knownTimeZone } from "@/lib/timezones";
import { AGENT_KINDS, ASSISTANT_PROVIDERS, type AgentKind, type AssistantProvider, type SettingsPatch } from "@/lib/types";

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
    // The key rides back to the form and nowhere else.
    return { ok: true, message: `${name} created.`, key: agent.key, slug: agent.slug };
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
