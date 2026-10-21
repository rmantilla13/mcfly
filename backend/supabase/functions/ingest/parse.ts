// Request parsing for the ingest function, kept free of I/O so it can be
// unit-tested (parse.test.ts). The shapes are documented in docs/AGENTS.md;
// this turns whatever an agent sent into exactly what the ingest_* SQL
// functions take, or says what's wrong in one sentence.

export type Feed = "briefs" | "quotes" | "news" | "projects" | "metrics" | "dashboards" | "events" | "todos";
export const FEEDS: Feed[] = ["briefs", "quotes", "news", "projects", "metrics", "dashboards", "events", "todos"];

export type Brief = {
  id?: string;
  title: string;
  body: string;
  kind: "hourly" | "daily" | "alert" | "update";
  published_at?: string;
  expires_at?: string;
};

export type Quote = {
  symbol: string;
  name?: string;
  price: number;
  change?: number;
  change_pct?: number;
  currency?: string;
  note?: string;
  as_of?: string;
  data?: Record<string, unknown>;
};

export type NewsItem = { id?: string; h: string; t: string; url: string; image?: string };
export type NewsSection = { key: string; name: string; items: NewsItem[] };
export type NewsReport = {
  slug: string;
  date?: string;
  report_date?: string;
  hero?: string;
  published_at?: string;
  sections: NewsSection[];
};

export type ProjectUpdate = {
  kind: "note" | "commit" | "pr" | "ci" | "deploy" | "alert" | "done";
  text: string;
  url?: string;
  at?: string;
};
export type Project = {
  key: string;
  name: string;
  kind: "code" | "task" | "launch" | "other";
  status: "active" | "blocked" | "paused" | "done";
  progress?: number;
  summary?: string;
  next_step?: string;
  link?: string;
  color?: string;
  sort_order?: number;
  data?: Record<string, unknown>;
  stages?: string[];
  stage?: string | null;
  updates?: ProjectUpdate[];
};

export type Metric = {
  key: string;
  label?: string;
  value: number;
  unit?: string;
  delta?: number;
  delta_pct?: number;
  note?: string;
  as_of?: string;
  group?: string;
  data?: Record<string, unknown>;
};

export type Widget =
  | { type: "metric"; label: string; value: number; unit?: string; delta?: number; delta_pct?: number }
  | { type: "status"; label: string; state: "ok" | "warn" | "down" | "unknown"; detail?: string }
  | { type: "progress"; label: string; value: number; max: number; unit?: string }
  | { type: "list"; title?: string; items: string[] }
  | { type: "text"; title?: string; body: string }
  | { type: "chart"; label: string; points: number[]; unit?: string };
export type Dashboard = {
  key: string;
  title: string;
  subtitle?: string;
  sort_order?: number;
  widgets: Widget[];
};

export type CalendarEvent = {
  id?: string;
  calendar: string;
  title: string;
  starts_at: string;
  ends_at?: string;
  all_day?: boolean;
  description?: string;
  location?: string;
  color?: string;
  url?: string;
  data?: Record<string, unknown>;
};

// A todo or a reminder. A reminder needs due_at (a time); a todo may have a
// due time, or a due day with all_day.
export type Todo = {
  id?: string;
  kind: "todo" | "reminder";
  title: string;
  notes?: string;
  due_at?: string;
  all_day?: boolean;
  done?: boolean;
  data?: Record<string, unknown>;
};

export type Parsed =
  | { feed: "briefs"; briefs: Brief[] }
  | { feed: "quotes"; quotes: Quote[]; as_of?: string }
  | { feed: "news"; report: NewsReport; resolveImages: boolean }
  | { feed: "projects"; projects: Project[] }
  | { feed: "metrics"; metrics: Metric[]; as_of?: string }
  | { feed: "dashboards"; dashboards: Dashboard[] }
  | { feed: "events"; events: CalendarEvent[]; calendar?: string; replace: boolean }
  | { feed: "todos"; todos: Todo[] };

type Fail = { error: string };

const KINDS = new Set(["hourly", "daily", "alert", "update"]);
const PROJECT_KINDS = new Set(["code", "task", "launch", "other"]);
const PROJECT_STATUSES = new Set(["active", "blocked", "paused", "done"]);
const UPDATE_KINDS = new Set(["note", "commit", "pr", "ci", "deploy", "alert", "done"]);
const WIDGET_TYPES = new Set(["metric", "status", "progress", "list", "text", "chart"]);
const STATES = new Set(["ok", "warn", "down", "unknown"]);
const SYMBOL = /^[A-Z0-9.^=:-]{1,16}$/;
const SLUG = /^[a-z0-9][a-z0-9-]{0,63}$/;
const SECTION_KEY = /^[a-z0-9_-]{1,32}$/;
const ITEM_KEY = /^[A-Za-z0-9_.-]{1,64}$/;
const PROJECT_KEY = /^[A-Za-z0-9][A-Za-z0-9._/-]{0,119}$/;
const LOWER_KEY = /^[a-z0-9][a-z0-9._-]{0,63}$/;
const HTTP = /^https?:\/\/\S+$/i;
const COLOR = /^#[0-9a-f]{6}$/i;

export const MAX_BRIEFS = 200;
export const MAX_QUOTES = 500;
export const MAX_NEWS_ITEMS = 500;
export const MAX_PROJECTS = 100;
export const MAX_UPDATES = 20;
export const MAX_STAGES = 12;
export const MAX_METRICS = 500;
export const MAX_DASHBOARDS = 20;
export const MAX_WIDGETS = 40;
export const MAX_LIST_ITEMS = 20;
export const MAX_POINTS = 120;
export const MAX_EVENTS = 1000;
export const MAX_TODOS = 200;

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

// The feed named by the request path: /ingest/briefs, /functions/v1/ingest/news, ...
// Nothing after "ingest" means the body names it with `type` or `feed`.
export function feedFromPath(pathname: string): Feed | "" | null {
  const parts = pathname.split("/").filter(Boolean);
  const at = parts.lastIndexOf("ingest");
  const rest = at < 0 ? parts : parts.slice(at + 1);
  if (rest.length === 0) return "";
  if (rest.length === 1 && FEEDS.includes(rest[0] as Feed)) return rest[0] as Feed;
  return null;
}

export function feedFromBody(body: unknown): Feed | null {
  if (!isObject(body)) return null;
  const named = body.type ?? body.feed;
  if (typeof named === "string" && FEEDS.includes(named as Feed)) return named as Feed;
  if (Array.isArray(body.briefs) || isObject(body.brief)) return "briefs";
  if (Array.isArray(body.quotes) || isObject(body.quote)) return "quotes";
  if (Array.isArray(body.sections)) return "news";
  if (Array.isArray(body.projects) || isObject(body.project)) return "projects";
  if (Array.isArray(body.metrics) || isObject(body.metric)) return "metrics";
  if (Array.isArray(body.dashboards) || isObject(body.dashboard)) return "dashboards";
  if (Array.isArray(body.events) || isObject(body.event)) return "events";
  if (Array.isArray(body.todos) || isObject(body.todo)) return "todos";
  return null;
}

// A trimmed string field, or undefined when it is absent or blank.
function str(v: unknown, max: number): string | undefined {
  if (typeof v !== "string") return undefined;
  const s = v.trim();
  return s ? s.slice(0, max) : undefined;
}

// An ISO-8601 timestamp, normalized, or an error for anything Date can't read.
function when(v: unknown, what: string): string | undefined | Fail {
  if (v == null || v === "") return undefined;
  if (typeof v !== "string" || Number.isNaN(Date.parse(v))) return { error: `${what} must be an ISO-8601 timestamp` };
  return new Date(v).toISOString();
}

function num(v: unknown): number | undefined | null {
  if (v == null || v === "") return undefined;
  const n = typeof v === "number" ? v : typeof v === "string" ? Number(v.replace(/[,$%\s]/g, "")) : NaN;
  return Number.isFinite(n) ? n : null; // null: present but unreadable
}

// A whole number (sort orders), from a number or a numeric string.
function int(v: unknown): number | undefined | null {
  const n = num(v);
  return n == null ? n : Number.isInteger(n) ? n : null;
}

const isFail = (v: unknown): v is Fail => isObject(v) && typeof v.error === "string";

// The list an agent sent: { <plural>: [...] } | { <singular>: {...} } | [...] |
// one bare object (recognised by `marker`), or an error quoting the shape.
function listOf(body: unknown, plural: string, singular: string, marker: string, shape: string): unknown[] | Fail {
  if (Array.isArray(body)) return body;
  if (isObject(body) && Array.isArray(body[plural])) return body[plural] as unknown[];
  if (isObject(body) && isObject(body[singular])) return [body[singular]];
  if (isObject(body) && marker in body) return [body];
  return { error: `send { ${plural}: [${shape}] } or one ${shape}` };
}

// { briefs: [...] } | { brief: {...} } | [...] | {...}
export function parseBriefs(body: unknown): { briefs: Brief[] } | Fail {
  let list: unknown;
  if (Array.isArray(body)) list = body;
  else if (isObject(body) && Array.isArray(body.briefs)) list = body.briefs;
  else if (isObject(body) && isObject(body.brief)) list = [body.brief];
  else if (isObject(body) && "title" in body) list = [body];
  else return { error: "send { briefs: [{ title, body }] } or one { title, body }" };
  const items = list as unknown[];
  if (items.length === 0) return { error: "no briefs in the request" };
  if (items.length > MAX_BRIEFS) return { error: `at most ${MAX_BRIEFS} briefs per push` };
  const briefs: Brief[] = [];
  for (const [i, raw] of items.entries()) {
    if (!isObject(raw)) return { error: `brief ${i + 1} must be an object` };
    const title = str(raw.title, 200);
    if (!title) return { error: `brief ${i + 1} needs a title` };
    const body = typeof raw.body === "string" ? raw.body.slice(0, 20000) : typeof raw.text === "string" ? raw.text.slice(0, 20000) : "";
    const kind = str(raw.kind, 16) ?? "update";
    if (!KINDS.has(kind)) return { error: `brief ${i + 1}: kind must be hourly, daily, alert or update` };
    const published = when(raw.published_at ?? raw.at, `brief ${i + 1}: published_at`);
    if (isFail(published)) return published;
    const expires = when(raw.expires_at, `brief ${i + 1}: expires_at`);
    if (isFail(expires)) return expires;
    const id = str(raw.id ?? raw.external_id, 120);
    briefs.push({
      ...(id ? { id } : {}),
      title,
      body,
      kind: kind as Brief["kind"],
      ...(published ? { published_at: published } : {}),
      ...(expires ? { expires_at: expires } : {}),
    });
  }
  return { briefs };
}

// { quotes: [...], as_of? } | { quote: {...} } | [...] | {...}
export function parseQuotes(body: unknown): { quotes: Quote[]; as_of?: string } | Fail {
  let list: unknown;
  let asOfRaw: unknown;
  if (Array.isArray(body)) list = body;
  else if (isObject(body) && Array.isArray(body.quotes)) {
    list = body.quotes;
    asOfRaw = body.as_of;
  } else if (isObject(body) && isObject(body.quote)) list = [body.quote];
  else if (isObject(body) && "symbol" in body) list = [body];
  else return { error: "send { quotes: [{ symbol, price }] } or one { symbol, price }" };
  const asOf = when(asOfRaw, "as_of");
  if (isFail(asOf)) return asOf;
  const items = list as unknown[];
  if (items.length === 0) return { error: "no quotes in the request" };
  if (items.length > MAX_QUOTES) return { error: `at most ${MAX_QUOTES} quotes per push` };
  const quotes: Quote[] = [];
  for (const [i, raw] of items.entries()) {
    if (!isObject(raw)) return { error: `quote ${i + 1} must be an object` };
    const symbol = str(raw.symbol ?? raw.ticker, 16)?.toUpperCase();
    if (!symbol || !SYMBOL.test(symbol)) return { error: `quote ${i + 1}: symbol must be 1 to 16 letters, digits or . ^ = : -` };
    const price = num(raw.price ?? raw.last);
    if (price === undefined) return { error: `${symbol} has no price` };
    if (price === null) return { error: `${symbol}: price must be a number` };
    const change = num(raw.change);
    if (change === null) return { error: `${symbol}: change must be a number` };
    const changePct = num(raw.change_pct ?? raw.change_percent ?? raw.changePercent);
    if (changePct === null) return { error: `${symbol}: change_pct must be a number` };
    const currency = str(raw.currency, 10)?.toUpperCase();
    if (currency && !/^[A-Z]{3}$/.test(currency)) return { error: `${symbol}: currency must be a 3-letter code` };
    const at = when(raw.as_of ?? raw.at, `${symbol}: as_of`);
    if (isFail(at)) return at;
    const name = str(raw.name, 120);
    const note = str(raw.note ?? raw.comment, 2000);
    quotes.push({
      symbol,
      price,
      ...(name ? { name } : {}),
      ...(change !== undefined ? { change } : {}),
      ...(changePct !== undefined ? { change_pct: changePct } : {}),
      ...(currency ? { currency } : {}),
      ...(note ? { note } : {}),
      ...(at ? { as_of: at } : {}),
      ...(isObject(raw.data) ? { data: raw.data } : {}),
    });
  }
  return { quotes, ...(asOf ? { as_of: asOf } : {}) };
}

// The Daily Pulse items JSON (docs/AGENTS.md). `headline`/`takeaway` are
// taken as well as `h`/`t`, and `image` is optional.
export function parseNews(body: unknown): { report: NewsReport; resolveImages: boolean } | Fail {
  if (!isObject(body)) return { error: "send the Daily Pulse items JSON: { date, slug, hero, sections }" };
  const report = isObject(body.report) ? body.report : body;
  const slug = str(report.slug, 64)?.toLowerCase();
  if (!slug || !SLUG.test(slug)) return { error: "slug must be like 2026-10-14 (lower-case letters, digits and dashes)" };
  if (!Array.isArray(report.sections) || report.sections.length === 0) return { error: "sections must be a non-empty list" };
  if (report.sections.length > 20) return { error: "at most 20 sections" };
  const published = when(report.published_at, "published_at");
  if (isFail(published)) return published;
  const reportDate = str(report.report_date, 10);
  if (reportDate && !/^\d{4}-\d{2}-\d{2}$/.test(reportDate)) return { error: "report_date must be YYYY-MM-DD" };
  const sections: NewsSection[] = [];
  let count = 0;
  for (const [s, rawSection] of (report.sections as unknown[]).entries()) {
    if (!isObject(rawSection)) return { error: `section ${s + 1} must be an object` };
    const key = str(rawSection.key, 32)?.toLowerCase();
    if (!key || !SECTION_KEY.test(key)) return { error: `section ${s + 1} needs a short key (like s, a or i)` };
    const name = str(rawSection.name, 80) ?? key;
    if (!Array.isArray(rawSection.items)) return { error: `section ${name} needs items` };
    const items: NewsItem[] = [];
    for (const [i, raw] of (rawSection.items as unknown[]).entries()) {
      if (!isObject(raw)) return { error: `${name} item ${i + 1} must be an object` };
      const h = str(raw.h ?? raw.headline ?? raw.title, 300);
      if (!h) return { error: `${name} item ${i + 1} needs a headline (h)` };
      const url = str(raw.url ?? raw.link, 2000);
      if (!url || !HTTP.test(url)) return { error: `${name}: "${h}" needs an http(s) source url` };
      const id = str(raw.id, 64);
      if (id && !ITEM_KEY.test(id)) return { error: `${name}: "${h}" has an unusable id` };
      const image = str(raw.image ?? raw.image_url, 2000);
      if (image && !HTTP.test(image)) return { error: `${name}: "${h}" has an unusable image URL` };
      const t = typeof raw.t === "string" ? raw.t : typeof raw.takeaway === "string" ? raw.takeaway : "";
      items.push({ ...(id ? { id } : {}), h, t: t.trim().slice(0, 2000), url, ...(image ? { image } : {}) });
      count++;
    }
    sections.push({ key, name, items });
  }
  if (count === 0) return { error: "the report has no items" };
  if (count > MAX_NEWS_ITEMS) return { error: `at most ${MAX_NEWS_ITEMS} items per report` };
  const date = str(report.date, 40);
  const hero = str(report.hero, 64);
  const resolveImages = body.resolve_images !== false && report.resolve_images !== false;
  return {
    report: {
      slug,
      ...(date ? { date } : {}),
      ...(reportDate ? { report_date: reportDate } : {}),
      ...(hero ? { hero } : {}),
      ...(published ? { published_at: published } : {}),
      sections,
    },
    resolveImages,
  };
}

// { projects: [...] } | { project: {...} } | [...] | one { key, name, ... }
export function parseProjects(body: unknown): { projects: Project[] } | Fail {
  const items = listOf(body, "projects", "project", "key", "{ key, name }");
  if (isFail(items)) return items;
  if (items.length === 0) return { error: "no projects in the request" };
  if (items.length > MAX_PROJECTS) return { error: `at most ${MAX_PROJECTS} projects per push` };
  const projects: Project[] = [];
  for (const [i, raw] of items.entries()) {
    if (!isObject(raw)) return { error: `project ${i + 1} must be an object` };
    const key = str(raw.key ?? raw.id, 120);
    if (!key || !PROJECT_KEY.test(key)) return { error: `project ${i + 1}: key must be 1 to 120 letters, digits or . _ / -` };
    const name = str(raw.name, 120) ?? key;
    const kind = str(raw.kind, 16) ?? "other";
    if (!PROJECT_KINDS.has(kind)) return { error: `project ${key}: kind must be code, task, launch or other` };
    const status = str(raw.status, 16) ?? "active";
    if (!PROJECT_STATUSES.has(status)) return { error: `project ${key}: status must be active, blocked, paused or done` };
    const progress = num(raw.progress);
    if (progress === null || (progress !== undefined && (progress < 0 || progress > 100))) {
      return { error: `project ${key}: progress must be a number from 0 to 100` };
    }
    const link = str(raw.link ?? raw.url, 2000);
    if (link && !HTTP.test(link)) return { error: `project ${key}: link must be an http(s) URL` };
    const color = str(raw.color, 10);
    if (color && !COLOR.test(color)) return { error: `project ${key}: color must be #rrggbb` };
    const sortOrder = int(raw.sort_order);
    if (sortOrder === null) return { error: `project ${key}: sort_order must be a whole number` };
    const staging = projectStages(key, raw.stages, raw.stage);
    if (isFail(staging)) return staging;
    const updates: ProjectUpdate[] = [];
    if (raw.updates != null) {
      if (!Array.isArray(raw.updates)) return { error: `project ${key}: updates must be a list` };
      if (raw.updates.length > MAX_UPDATES) return { error: `project ${key}: at most ${MAX_UPDATES} updates` };
      for (const [u, rawUpdate] of (raw.updates as unknown[]).entries()) {
        if (!isObject(rawUpdate)) return { error: `project ${key} update ${u + 1} must be an object` };
        const text = str(rawUpdate.text ?? rawUpdate.message, 2000);
        if (!text) return { error: `project ${key} update ${u + 1} needs text` };
        const ukind = str(rawUpdate.kind, 16) ?? "note";
        if (!UPDATE_KINDS.has(ukind)) return { error: `project ${key} update ${u + 1}: kind must be note, commit, pr, ci, deploy, alert or done` };
        const url = str(rawUpdate.url ?? rawUpdate.link, 2000);
        if (url && !HTTP.test(url)) return { error: `project ${key} update ${u + 1}: url must be an http(s) URL` };
        const at = when(rawUpdate.at ?? rawUpdate.happened_at, `project ${key} update ${u + 1}: at`);
        if (isFail(at)) return at;
        updates.push({ kind: ukind as ProjectUpdate["kind"], text, ...(url ? { url } : {}), ...(at ? { at } : {}) });
      }
    }
    const summary = str(raw.summary, 2000);
    const nextStep = str(raw.next_step, 500);
    projects.push({
      key,
      name,
      kind: kind as Project["kind"],
      status: status as Project["status"],
      ...(progress !== undefined ? { progress: Math.round(progress) } : {}),
      ...(summary ? { summary } : {}),
      ...(nextStep ? { next_step: nextStep } : {}),
      ...(link ? { link } : {}),
      ...(color ? { color: color.toUpperCase() } : {}),
      ...(sortOrder !== undefined ? { sort_order: sortOrder } : {}),
      ...(isObject(raw.data) ? { data: raw.data } : {}),
      ...staging,
      ...(updates.length ? { updates } : {}),
    });
  }
  return { projects };
}

// A project's stages (a list of names; null or [] clears them) and the one
// it is in now (named in any case; null clears it). Each is left out when
// the agent left it out, so the project keeps what it had; a stage alone is
// checked against the stored stages by ingest_projects.
function projectStages(key: string, rawStages: unknown, rawStage: unknown): { stages?: string[]; stage?: string | null } | Fail {
  const out: { stages?: string[]; stage?: string | null } = {};
  if (rawStages === null) out.stages = [];
  else if (rawStages !== undefined) {
    if (!Array.isArray(rawStages)) return { error: `project ${key}: stages must be a list of names` };
    if (rawStages.length > MAX_STAGES) return { error: `project ${key}: at most ${MAX_STAGES} stages` };
    const stages: string[] = [];
    for (const s of rawStages as unknown[]) {
      const name = typeof s === "string" ? s.trim() : "";
      if (!name || name.length > 40) return { error: `project ${key}: each stage must be a name of 1 to 40 characters` };
      if (stages.some((x) => x.toLowerCase() === name.toLowerCase())) return { error: `project ${key}: stage "${name}" is listed twice` };
      stages.push(name);
    }
    out.stages = stages;
  }
  if (rawStage === undefined) return out;
  if (rawStage !== null && typeof rawStage !== "string") return { error: `project ${key}: stage must be the name of one of its stages` };
  const wanted = rawStage?.trim() || null;
  if (wanted && out.stages) {
    const match = out.stages.find((x) => x.toLowerCase() === wanted.toLowerCase());
    if (!match) return { error: out.stages.length ? `project ${key}: stage "${wanted}" is not one of its stages` : `project ${key}: a stage needs stages to be one of` };
    out.stage = match;
  } else out.stage = wanted ? wanted.slice(0, 40) : null;
  return out;
}

// { metrics: [...], as_of? } | { metric: {...} } | [...] | one { key, value }
export function parseMetrics(body: unknown): { metrics: Metric[]; as_of?: string } | Fail {
  const items = listOf(body, "metrics", "metric", "key", "{ key, value }");
  if (isFail(items)) return items;
  const asOf = when(isObject(body) && Array.isArray(body.metrics) ? body.as_of : undefined, "as_of");
  if (isFail(asOf)) return asOf;
  if (items.length === 0) return { error: "no metrics in the request" };
  if (items.length > MAX_METRICS) return { error: `at most ${MAX_METRICS} metrics per push` };
  const metrics: Metric[] = [];
  for (const [i, raw] of items.entries()) {
    if (!isObject(raw)) return { error: `metric ${i + 1} must be an object` };
    const key = str(raw.key ?? raw.id, 64)?.toLowerCase();
    if (!key || !LOWER_KEY.test(key)) return { error: `metric ${i + 1}: key must be 1 to 64 lower-case letters, digits or . _ -` };
    const value = num(raw.value);
    if (value === undefined) return { error: `${key} has no value` };
    if (value === null) return { error: `${key}: value must be a number` };
    const delta = num(raw.delta);
    if (delta === null) return { error: `${key}: delta must be a number` };
    const deltaPct = num(raw.delta_pct ?? raw.delta_percent ?? raw.deltaPercent);
    if (deltaPct === null) return { error: `${key}: delta_pct must be a number` };
    const at = when(raw.as_of ?? raw.at, `${key}: as_of`);
    if (isFail(at)) return at;
    const label = str(raw.label ?? raw.name, 80);
    const unit = str(raw.unit, 16);
    const note = str(raw.note ?? raw.comment, 2000);
    const group = str(raw.group ?? raw.group_name, 80);
    metrics.push({
      key,
      value,
      ...(label ? { label } : {}),
      ...(unit ? { unit } : {}),
      ...(delta !== undefined ? { delta } : {}),
      ...(deltaPct !== undefined ? { delta_pct: deltaPct } : {}),
      ...(note ? { note } : {}),
      ...(at ? { as_of: at } : {}),
      ...(group ? { group } : {}),
      ...(isObject(raw.data) ? { data: raw.data } : {}),
    });
  }
  return { metrics, ...(asOf ? { as_of: asOf } : {}) };
}

// One widget, with only the fields its type has, so what's stored is what
// the display knows how to draw.
function parseWidget(raw: unknown, where: string): Widget | Fail {
  if (!isObject(raw)) return { error: `${where} must be an object` };
  const type = str(raw.type, 16);
  if (!type || !WIDGET_TYPES.has(type)) return { error: `${where}: type must be metric, status, progress, list, text or chart` };
  const label = str(raw.label ?? raw.title, 200);
  const title = str(raw.title ?? raw.label, 200);
  const unit = str(raw.unit, 200);
  switch (type) {
    case "metric": {
      if (!label) return { error: `${where} needs a label` };
      const value = num(raw.value);
      if (value == null) return { error: `${where}: value must be a number` };
      const delta = num(raw.delta);
      if (delta === null) return { error: `${where}: delta must be a number` };
      const deltaPct = num(raw.delta_pct);
      if (deltaPct === null) return { error: `${where}: delta_pct must be a number` };
      return {
        type, label, value,
        ...(unit ? { unit } : {}),
        ...(delta !== undefined ? { delta } : {}),
        ...(deltaPct !== undefined ? { delta_pct: deltaPct } : {}),
      };
    }
    case "status": {
      if (!label) return { error: `${where} needs a label` };
      const state = str(raw.state ?? raw.status, 16)?.toLowerCase();
      if (!state || !STATES.has(state)) return { error: `${where}: state must be ok, warn, down or unknown` };
      const detail = str(raw.detail, 200);
      return { type, label, state: state as "ok", ...(detail ? { detail } : {}) };
    }
    case "progress": {
      if (!label) return { error: `${where} needs a label` };
      const value = num(raw.value);
      if (value == null) return { error: `${where}: value must be a number` };
      const max = num(raw.max); // undefined: not given (100); null: given but not a number
      if (max === null || (max !== undefined && max <= 0)) return { error: `${where}: max must be a number above 0` };
      return { type, label, value, max: max ?? 100, ...(unit ? { unit } : {}) };
    }
    case "list": {
      const items = raw.items;
      if (!Array.isArray(items) || items.length > MAX_LIST_ITEMS || items.some((it) => typeof it !== "string")) {
        return { error: `${where}: items must be a list of up to ${MAX_LIST_ITEMS} strings` };
      }
      const kept = (items as string[]).map((it) => it.trim().slice(0, 200)).filter(Boolean);
      return { type, ...(title ? { title } : {}), items: kept };
    }
    case "text": {
      const body = typeof raw.body === "string" ? raw.body.trim().slice(0, 2000) : typeof raw.text === "string" ? raw.text.trim().slice(0, 2000) : "";
      if (!body) return { error: `${where} needs a body` };
      return { type, ...(title ? { title } : {}), body };
    }
    default: { // chart
      if (!label) return { error: `${where} needs a label` };
      const points = raw.points ?? raw.values;
      if (!Array.isArray(points) || points.length === 0 || points.length > MAX_POINTS || points.some((p) => typeof p !== "number" || !Number.isFinite(p))) {
        return { error: `${where}: points must be a list of 1 to ${MAX_POINTS} numbers` };
      }
      return { type: "chart", label, points: points as number[], ...(unit ? { unit } : {}) };
    }
  }
}

// { dashboards: [...] } | { dashboard: {...} } | [...] | one { key, title, widgets }
export function parseDashboards(body: unknown): { dashboards: Dashboard[] } | Fail {
  const items = listOf(body, "dashboards", "dashboard", "widgets", "{ key, title, widgets }");
  if (isFail(items)) return items;
  if (items.length === 0) return { error: "no dashboards in the request" };
  if (items.length > MAX_DASHBOARDS) return { error: `at most ${MAX_DASHBOARDS} dashboards per push` };
  const dashboards: Dashboard[] = [];
  for (const [i, raw] of items.entries()) {
    if (!isObject(raw)) return { error: `dashboard ${i + 1} must be an object` };
    const key = str(raw.key ?? raw.id, 64)?.toLowerCase();
    if (!key || !LOWER_KEY.test(key)) return { error: `dashboard ${i + 1}: key must be 1 to 64 lower-case letters, digits or . _ -` };
    const title = str(raw.title ?? raw.name, 80) ?? key;
    const subtitle = str(raw.subtitle, 200);
    const sortOrder = int(raw.sort_order);
    if (sortOrder === null) return { error: `dashboard ${key}: sort_order must be a whole number` };
    if (!Array.isArray(raw.widgets) || raw.widgets.length === 0 || raw.widgets.length > MAX_WIDGETS) {
      return { error: `dashboard ${key}: widgets must be a list of 1 to ${MAX_WIDGETS} widgets` };
    }
    const widgets: Widget[] = [];
    for (const [w, rawWidget] of (raw.widgets as unknown[]).entries()) {
      const widget = parseWidget(rawWidget, `dashboard ${key} widget ${w + 1}`);
      if (isFail(widget)) return widget;
      widgets.push(widget);
    }
    dashboards.push({
      key,
      title,
      ...(subtitle ? { subtitle } : {}),
      ...(sortOrder !== undefined ? { sort_order: sortOrder } : {}),
      widgets,
    });
  }
  return { dashboards };
}

// { events: [...], calendar?, replace? } | { event: {...} } | [...] | one { title, starts_at }
export function parseEvents(body: unknown): { events: CalendarEvent[]; calendar?: string; replace: boolean } | Fail {
  const items = listOf(body, "events", "event", "starts_at", "{ title, starts_at }");
  if (isFail(items)) return items;
  const envelope = isObject(body) && Array.isArray(body.events) ? body : {};
  const calendar = str(envelope.calendar, 80);
  if (envelope.replace != null && typeof envelope.replace !== "boolean") return { error: "replace must be true or false" };
  const replace = envelope.replace === true;
  if (replace && !calendar) return { error: "replace needs a calendar name: the push is that calendar, whole" };
  if (items.length === 0) return { error: "no events in the request" };
  if (items.length > MAX_EVENTS) return { error: `at most ${MAX_EVENTS} events per push` };
  const events: CalendarEvent[] = [];
  for (const [i, raw] of items.entries()) {
    if (!isObject(raw)) return { error: `event ${i + 1} must be an object` };
    const title = str(raw.title ?? raw.summary, 300);
    if (!title) return { error: `event ${i + 1} needs a title` };
    const startsAt = when(raw.starts_at ?? raw.start, `event ${title}: starts_at`);
    if (isFail(startsAt)) return startsAt;
    if (!startsAt) return { error: `event ${title} needs starts_at` };
    const endsAt = when(raw.ends_at ?? raw.end, `event ${title}: ends_at`);
    if (isFail(endsAt)) return endsAt;
    if (endsAt && endsAt < startsAt) return { error: `event ${title}: ends_at must not be before starts_at` };
    if (raw.all_day != null && typeof raw.all_day !== "boolean") return { error: `event ${title}: all_day must be true or false` };
    const color = str(raw.color, 10);
    if (color && !COLOR.test(color)) return { error: `event ${title}: color must be #rrggbb` };
    const url = str(raw.url ?? raw.link, 2000);
    if (url && !HTTP.test(url)) return { error: `event ${title}: url must be an http(s) URL` };
    const id = str(raw.id ?? raw.external_id ?? raw.uid, 200);
    const own = str(raw.calendar, 80);
    const description = str(raw.description, 4000);
    const location = str(raw.location, 300);
    events.push({
      ...(id ? { id } : {}),
      calendar: own ?? calendar ?? "Calendar",
      title,
      starts_at: startsAt,
      ...(endsAt ? { ends_at: endsAt } : {}),
      ...(raw.all_day === true ? { all_day: true } : {}),
      ...(description ? { description } : {}),
      ...(location ? { location } : {}),
      ...(color ? { color: color.toUpperCase() } : {}),
      ...(url ? { url } : {}),
      ...(isObject(raw.data) ? { data: raw.data } : {}),
    });
  }
  return { events, ...(calendar ? { calendar } : {}), replace };
}

// { todos: [...] } | { todo: {...} } | [...] | one { title, kind? }
export function parseTodos(body: unknown): { todos: Todo[] } | Fail {
  const items = listOf(body, "todos", "todo", "title", "{ title, kind?, due_at? }");
  if (isFail(items)) return items;
  if (items.length === 0) return { error: "no todos in the request" };
  if (items.length > MAX_TODOS) return { error: `at most ${MAX_TODOS} todos per push` };
  const todos: Todo[] = [];
  for (const [i, raw] of items.entries()) {
    if (!isObject(raw)) return { error: `todo ${i + 1} must be an object` };
    const title = str(raw.title, 300);
    if (!title) return { error: `todo ${i + 1} needs a title` };
    const kind = raw.kind == null ? "todo" : raw.kind;
    if (kind !== "todo" && kind !== "reminder") return { error: `todo ${title}: kind must be todo or reminder` };
    const dueAt = when(raw.due_at ?? raw.due ?? raw.remind_at, `todo ${title}: due_at`);
    if (isFail(dueAt)) return dueAt;
    if (raw.all_day != null && typeof raw.all_day !== "boolean") return { error: `todo ${title}: all_day must be true or false` };
    if (raw.done != null && typeof raw.done !== "boolean") return { error: `todo ${title}: done must be true or false` };
    if (raw.all_day === true && !dueAt) return { error: `todo ${title}: all_day needs due_at (the day)` };
    if (kind === "reminder" && !dueAt) return { error: `reminder ${title} needs due_at: when to remind` };
    if (kind === "reminder" && raw.all_day === true) return { error: `reminder ${title} needs a time, not a whole day` };
    const id = str(raw.id ?? raw.external_id, 200);
    const notes = str(raw.notes ?? raw.description, 2000);
    todos.push({
      ...(id ? { id } : {}),
      kind,
      title,
      ...(notes ? { notes } : {}),
      ...(dueAt ? { due_at: dueAt } : {}),
      ...(raw.all_day === true ? { all_day: true } : {}),
      ...(typeof raw.done === "boolean" ? { done: raw.done } : {}),
      ...(isObject(raw.data) ? { data: raw.data } : {}),
    });
  }
  return { todos };
}

export function parse(feed: Feed, body: unknown): Parsed | Fail {
  switch (feed) {
    case "briefs": {
      const r = parseBriefs(body);
      return isFail(r) ? r : { feed, ...r };
    }
    case "quotes": {
      const r = parseQuotes(body);
      return isFail(r) ? r : { feed, ...r };
    }
    case "news": {
      const r = parseNews(body);
      return isFail(r) ? r : { feed, ...r };
    }
    case "projects": {
      const r = parseProjects(body);
      return isFail(r) ? r : { feed, ...r };
    }
    case "metrics": {
      const r = parseMetrics(body);
      return isFail(r) ? r : { feed, ...r };
    }
    case "dashboards": {
      const r = parseDashboards(body);
      return isFail(r) ? r : { feed, ...r };
    }
    case "events": {
      const r = parseEvents(body);
      return isFail(r) ? r : { feed, ...r };
    }
    case "todos": {
      const r = parseTodos(body);
      return isFail(r) ? r : { feed, ...r };
    }
  }
}

// The agent's key from `Authorization: Bearer mcf_…` or `X-Agent-Key: mcf_…`.
export function agentKey(headers: Headers): string | null {
  const direct = headers.get("x-agent-key")?.trim();
  if (direct) return direct;
  const match = headers.get("authorization")?.match(/^Bearer\s+(\S+)\s*$/i);
  return match ? match[1] : null;
}

export const KEY_SHAPE = /^mcf_[0-9a-f]{40}$/;
