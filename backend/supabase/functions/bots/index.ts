// bots: runs the Grok bots that are due (migration 20261015000005). For
// each: the bot's context (bot_context), one call to xAI's Responses API with
// web and X search, the answer checked like an agent's push, then stored
// through the same ingest functions under the bot's agent.
//
//   POST {}               the due ones, two at a time   (pg_cron, every 5 min)
//   POST { bot: "<id>" }  that one now                   ("Run now" in the console)
//
// Who may call: pg_cron with `x-mcfly-cron: <the Vault secret>` (../_shared/cron.ts), or a
// platform admin with their own JWT. Needs the XAI_API_KEY secret.
//
// Answers { ok: true, ran: [{ name, title } | { name, error }] }.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { isCronCall } from "../_shared/cron.ts";
import { bearerToken, isUuid, json, preflight, readJson } from "../_shared/http.ts";
import { readResponse, requestBody, toPush, XAI_RESPONSES_URL, type Bot, type Context } from "./run.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const XAI_KEY = Deno.env.get("XAI_API_KEY") ?? "";
const DEFAULT_MODEL = Deno.env.get("GROK_BOT_MODEL") ?? "";

const service = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

async function isAdmin(jwt: string): Promise<boolean> {
  const db = createClient(SUPABASE_URL, ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  const { data, error } = await db.rpc("is_platform_admin");
  return !error && data === true;
}

type Claimed = Bot & { id: string; agent_id: string; scopes: string[]; run_id: number };

async function askGrok(bot: Bot, ctx: Context): Promise<{ text: string; sources: string[]; model?: string } | { error: string }> {
  if (!XAI_KEY) return { error: "add the XAI_API_KEY secret (Supabase → Edge Functions → Secrets)" };
  let res: Response;
  try {
    res = await fetch(XAI_RESPONSES_URL, {
      method: "POST",
      headers: { Authorization: `Bearer ${XAI_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify(requestBody({ ...bot, model: bot.model || DEFAULT_MODEL }, ctx)),
      signal: AbortSignal.timeout(140_000),
    });
  } catch (err) {
    return { error: err instanceof Error && err.name === "TimeoutError" ? "Grok took too long (over 140 s)" : "couldn't reach xAI" };
  }
  const body = await res.json().catch(() => null);
  if (!res.ok) {
    const message = (body as { error?: { message?: string } | string } | null)?.error;
    const text = typeof message === "string" ? message : message?.message;
    if (res.status === 401 || res.status === 403) return { error: "xAI refused the API key; check XAI_API_KEY" };
    if (res.status === 429) return { error: "xAI is rate-limiting; it will try again on schedule" };
    return { error: `xAI answered ${res.status}${text ? `: ${text.slice(0, 200)}` : ""}` };
  }
  const read = readResponse(body);
  return read.text ? read : { error: "Grok's answer was empty" };
}

async function runOne(bot: Claimed): Promise<{ name: string; title?: string; error?: string }> {
  const finish = async (status: "ok" | "error", extra: { title?: string; error?: string; sources?: number; model?: string }) => {
    const { error } = await service.rpc("bot_run_finished", {
      run: bot.run_id, status, title: extra.title ?? null, error: extra.error ?? null, sources: extra.sources ?? 0, model: extra.model ?? null,
    });
    if (error) console.error("bot_run_finished failed:", error.message);
  };
  const feed = bot.output === "news" ? "news" : "briefs";
  try {
    const { data: ctx } = await service.rpc("bot_context", { agent: bot.agent_id });
    const answer = await askGrok(bot, (ctx ?? {}) as Context);
    if ("error" in answer) {
      await service.rpc("record_ingest", { agent: bot.agent_id, feed, count: 0, status: "error", message: answer.error });
      await finish("error", { error: answer.error });
      return { name: bot.name, error: answer.error };
    }
    const push = toPush(bot, answer.text, bot.run_id);
    if ("error" in push) {
      await service.rpc("record_ingest", { agent: bot.agent_id, feed, count: 0, status: "error", message: push.error });
      await finish("error", { error: push.error, sources: answer.sources.length, model: answer.model });
      return { name: bot.name, error: push.error };
    }
    let title = "";
    let count = 0;
    if (push.feed === "briefs") {
      const { error } = await service.rpc("ingest_briefs", { agent: bot.agent_id, items: push.briefs });
      if (error) throw new Error(error.message);
      title = push.briefs[0].title;
      count = push.briefs.length;
    } else if (push.feed === "news") {
      const { error } = await service.rpc("ingest_news", { agent: bot.agent_id, report: push.report });
      if (error) throw new Error(error.message);
      const hero = push.report.sections.flatMap((s) => s.items).find((i) => i.id === push.report.hero);
      title = hero?.h ?? `Report for ${push.report.date ?? push.report.slug}`;
      count = push.report.sections.reduce((n, s) => n + s.items.length, 0);
    }
    await service.rpc("record_ingest", { agent: bot.agent_id, feed, count, status: "ok", message: null });
    await finish("ok", { title, sources: answer.sources.length, model: answer.model });
    service.rpc("prune_feed").then(({ error }) => error && console.error("prune_feed failed:", error.message));
    return { name: bot.name, title };
  } catch (err) {
    const message = err instanceof Error ? err.message : "something went wrong";
    console.error(`bot ${bot.name} failed:`, err);
    await finish("error", { error: message });
    return { name: bot.name, error: message };
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const cron = await isCronCall(req, service);
  if (!cron) {
    const jwt = bearerToken(req);
    if (!jwt || !(await isAdmin(jwt))) return json({ error: "sign in as the admin" }, 401);
  }
  const read = await readJson(req);
  if ("error" in read) return read.error;
  const body = (typeof read.body === "object" && read.body !== null ? read.body : {}) as Record<string, unknown>;
  const one = typeof body.bot === "string" && isUuid(body.bot) ? body.bot : null;

  const { data, error } = await service.rpc("bots_claim", { lim: one ? 1 : 2, bot: one });
  if (error) {
    console.error("bots_claim failed:", error.message);
    return json({ error: "couldn't read the bots; try again in a moment" }, 503);
  }
  const claimed = (data ?? []) as Claimed[];
  if (one && !claimed.length) return json({ error: "that bot is already running or gone" }, 409);
  const ran = await Promise.all(claimed.map(runOne));
  return json({ ok: true, ran });
});
