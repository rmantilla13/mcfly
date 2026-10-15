// Display formatting. Dates are shown in UTC (the server renders them, and
// an admin reading from anywhere should see the same thing); relative times
// carry the exact timestamp in a tooltip.

const integer = new Intl.NumberFormat("en-US");
const compactFormat = new Intl.NumberFormat("en-US", { notation: "compact", maximumFractionDigits: 1 });
const dateFormat = new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", year: "numeric", timeZone: "UTC" });
const shortDate = new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", timeZone: "UTC" });
const dateTimeFormat = new Intl.DateTimeFormat("en-US", {
  month: "short",
  day: "numeric",
  year: "numeric",
  hour: "numeric",
  minute: "2-digit",
  timeZone: "UTC",
  timeZoneName: "short",
});

export const formatNumber = (n: number) => integer.format(n);
export const formatCompact = (n: number) => (Math.abs(n) < 10_000 ? integer.format(n) : compactFormat.format(n));

// Timestamps come from agent-written rows, and Postgres also stores values
// JavaScript can't read ('infinity', years past 9999). Those are shown as
// they are instead of throwing, so one odd row can't take a page down.
function format(f: Intl.DateTimeFormat, iso: string): string {
  const t = Date.parse(iso);
  return Number.isFinite(t) ? f.format(t) : iso;
}

export function formatDate(iso: string | null | undefined): string {
  return iso ? format(dateFormat, iso) : "—";
}

export function formatShortDate(iso: string): string {
  return format(shortDate, iso.length === 10 ? `${iso}T00:00:00Z` : iso);
}

export function formatDateTime(iso: string | null | undefined): string {
  return iso ? format(dateTimeFormat, iso) : "—";
}

const UNITS: [Intl.RelativeTimeFormatUnit, number][] = [
  ["year", 365 * 86_400],
  ["month", 30 * 86_400],
  ["week", 7 * 86_400],
  ["day", 86_400],
  ["hour", 3_600],
  ["minute", 60],
];
const relative = new Intl.RelativeTimeFormat("en-US", { numeric: "auto", style: "short" });

export function formatRelative(iso: string | null | undefined, now = Date.now()): string {
  if (!iso) return "never";
  const t = Date.parse(iso);
  if (!Number.isFinite(t)) return iso;
  const seconds = Math.round((t - now) / 1000);
  if (Math.abs(seconds) < 60) return seconds <= 0 ? "just now" : "in a moment";
  for (const [unit, size] of UNITS) {
    if (Math.abs(seconds) >= size) return relative.format(Math.trunc(seconds / size), unit);
  }
  return relative.format(Math.trunc(seconds / 60), "minute");
}

export const plural = (n: number, one: string, many = `${one}s`) => `${formatNumber(n)} ${n === 1 ? one : many}`;

// A display counts as online when it has checked in within this window
// (admin_overview's devices_online uses the same 15 minutes).
export const ONLINE_WINDOW_MS = 15 * 60_000;

export function isOnline(lastSeen: string | null | undefined, now = Date.now()): boolean {
  if (!lastSeen) return false;
  const t = Date.parse(lastSeen);
  return Number.isFinite(t) && now - t <= ONLINE_WINDOW_MS;
}

// The first `max` characters of a brief's body on one line, for a table cell.
export function preview(text: string, max = 160): string {
  const flat = text.replace(/\s+/g, " ").trim();
  return flat.length <= max ? flat : `${flat.slice(0, max).trimEnd()}…`;
}

// A quote's price in its currency. Agents send any three letters, and Intl
// shows an unknown code as the code itself, so this never throws for a row.
export function formatPrice(price: number | null | undefined, currency: string | null | undefined): string {
  if (price == null || !Number.isFinite(price)) return "—";
  const code = currency && /^[A-Z]{3}$/.test(currency) ? currency : "USD";
  try {
    return new Intl.NumberFormat("en-US", { style: "currency", currency: code, maximumFractionDigits: 2 }).format(price);
  } catch {
    return `${price.toFixed(2)} ${code}`;
  }
}

// "+2.78 (+1.13%)", "−3.10 (−1.62%)", or whichever half the agent sent.
export function formatChange(change: number | null | undefined, pct: number | null | undefined): string {
  const parts: string[] = [];
  if (change != null && Number.isFinite(change)) parts.push(signed(change, 2));
  if (pct != null && Number.isFinite(pct)) parts.push(`${parts.length ? "(" : ""}${signed(pct, 2)}%${parts.length ? ")" : ""}`);
  return parts.length ? parts.join(" ") : "—";
}

function signed(n: number, digits: number): string {
  const text = Math.abs(n).toFixed(digits);
  return n > 0 ? `+${text}` : n < 0 ? `−${text}` : text;
}

// Up, down or flat, from whichever of change and change_pct is present.
export function changeDirection(change: number | null | undefined, pct: number | null | undefined): "up" | "down" | "flat" {
  const n = change ?? pct ?? 0;
  return n > 0 ? "up" : n < 0 ? "down" : "flat";
}

// An agent color that is safe to put in a style attribute, or null. Colors
// are checked by the database, but a row from an older backend or a fixture
// could hold anything, and anything but a hex color ("red;position:fixed",
// "url(https://…)") would be CSS in the admin's page.
export function cssColor(value: unknown): string | null {
  const v = typeof value === "string" ? value.trim() : "";
  return /^#(?:[0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(v) ? v : null;
}

// Audit action ids (docs/PLATFORM_SPEC.md §1.6) → words.
const ACTIONS: Record<string, string> = {
  create_agent: "Created agent",
  rotate_agent_key: "Rotated agent key",
  update_agent: "Updated agent",
  revoke_agent: "Revoked agent",
  delete_agent: "Deleted agent",
  delete_brief: "Deleted brief",
  set_symbol: "Changed symbol",
  delete_symbol: "Deleted symbol",
  delete_news_report: "Deleted news report",
  rename_device: "Renamed display",
  revoke_device: "Revoked display",
  pair_device: "Paired display",
  update_settings: "Updated settings",
  set_admin: "Changed admin access",
  delete_project: "Deleted project",
  set_metric: "Changed metric",
  delete_metric: "Deleted metric",
  set_dashboard: "Changed dashboard",
  delete_dashboard: "Deleted dashboard",
  delete_event: "Deleted event",
  delete_calendar: "Removed calendar",
  set_agent_scopes: "Changed agent permissions",
  save_memory: "Saved a note",
  delete_memory: "Deleted a note",
  add_calendar_source: "Added a calendar",
  update_calendar_source: "Changed a calendar",
  delete_calendar_source: "Removed a calendar",
  update_device_settings: "Changed display settings",
  save_bot: "Saved a Grok bot",
};

// set_symbol, set_metric and set_dashboard record only what changed; the
// words follow the first thing they changed.
const SET_WORDS: Record<string, string> = { set_symbol: "symbol", set_metric: "metric", set_dashboard: "dashboard" };

export function describeAction(action: string, details: Record<string, unknown> = {}): string {
  const noun = SET_WORDS[action];
  if (noun) {
    if (details.hidden === true) return `Hid ${noun}`;
    if (details.hidden === false) return `Showed ${noun}`;
    if (details.sort_order !== undefined) return `Reordered ${noun}`;
    if (details.label !== undefined || details.group_name !== undefined) return `Relabeled ${noun}`;
    return `Changed ${noun}`;
  }
  if (action === "set_admin") return details.make_admin ? "Made admin" : "Removed admin";
  return ACTIONS[action] ?? action.replaceAll("_", " ");
}
