// scripts/google-calendar-push.gs, run outside Google: the script's own code
// with stand-ins for CalendarApp, Utilities and UrlFetchApp, its output fed
// through McFly's real events parser.
//
//   deno test --allow-read scripts/google-calendar-push.test.ts
import { assert, assertEquals } from "jsr:@std/assert@1";
import { parseEvents } from "../backend/supabase/functions/ingest/parse.ts";

const ZONE = "America/Chicago";
const src = await Deno.readTextFile(new URL("./google-calendar-push.gs", import.meta.url));

// Utilities.formatDate, for the patterns the script uses (Java SimpleDateFormat subset).
function formatDate(d: Date, zone: string, pattern: string): string {
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-CA", { timeZone: zone, year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23" }).formatToParts(d).map((x) => [x.type, x.value]));
  const asUtc = Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second);
  const off = Math.round((asUtc - Math.floor(d.getTime() / 1000) * 1000) / 60000);
  const a = Math.abs(off);
  const xxx = `${off < 0 ? "-" : "+"}${String(Math.floor(a / 60)).padStart(2, "0")}:${String(a % 60).padStart(2, "0")}`;
  return pattern.replace("yyyy", p.year).replace("MM", p.month).replace("dd", p.day).replace("'T'", "T").replace("XXX", xxx);
}
const localMidnight = (day: string) => new Date(formatDate(new Date(`${day}T12:00:00Z`), ZONE, `${day}'T'00:00:00XXX`).replace(/^.{10}/, day));

type Ev = { id: string; title: string; start?: Date; end?: Date; allDay?: [string, string]; where?: string; status?: string };
const ev = (e: Ev) => ({
  getId: () => e.id, getTitle: () => e.title, getLocation: () => e.where ?? "",
  getMyStatus: () => e.status ?? "OWNER", isAllDayEvent: () => !!e.allDay,
  getStartTime: () => e.start ?? localMidnight(e.allDay![0]), getEndTime: () => e.end ?? localMidnight(e.allDay![1]),
  getAllDayStartDate: () => localMidnight(e.allDay![0]), getAllDayEndDate: () => localMidnight(e.allDay![1]),
});
const events = [
  ev({ id: "standup@google.com", title: "Standup", start: new Date("2026-10-16T14:30:00Z"), end: new Date("2026-10-16T14:45:00Z"), where: "Zoom" }),
  ev({ id: "standup@google.com", title: "Standup", start: new Date("2026-10-17T14:30:00Z"), end: new Date("2026-10-17T14:45:00Z") }),
  ev({ id: "offsite@google.com", title: "Offsite", allDay: ["2026-10-20", "2026-10-21"] }),
  ev({ id: "trip@google.com", title: "Trip", allDay: ["2026-10-31", "2026-11-03"], where: "x".repeat(400) }), // across DST (Nov 1)
  ev({ id: "declined@google.com", title: "Declined sync", start: new Date("2026-10-18T15:00:00Z"), end: new Date("2026-10-18T16:00:00Z"), status: "NO" }),
  ev({ id: "busy@google.com", title: "", start: new Date("2026-10-19T15:00:00Z"), end: new Date("2026-10-19T16:00:00Z"), status: "YES" }),
];
const calendar = { getEvents: () => events, getColor: () => "#9FC6E7", getName: () => "ARMRA" };

let fetched: { url: string; opts: Record<string, unknown> } | null = null;
const props: Record<string, string> = { MCFLY_KEY: "mcf_test", CALENDAR_ID: "c_armra@group.calendar.google.com" };
const mocks = {
  Session: { getScriptTimeZone: () => ZONE },
  Utilities: { formatDate },
  CalendarApp: { GuestStatus: { NO: "NO" }, getCalendarById: (id: string) => (id === props.CALENDAR_ID ? calendar : null) },
  PropertiesService: { getScriptProperties: () => ({ getProperty: (k: string) => props[k] ?? null }) },
  UrlFetchApp: { fetch: (url: string, opts: Record<string, unknown>) => { fetched = { url, opts }; return { getResponseCode: () => 200, getContentText: () => "{}" }; } },
  ScriptApp: {}, console,
};
const gas = new Function(...Object.keys(mocks), `${src}\nreturn { mcflyPayload, pushToMcFly };`)(...Object.values(mocks));

const chicagoDay = (iso: string) => formatDate(new Date(iso), ZONE, "yyyy-MM-dd");

Deno.test("the payload passes McFly's own events parser", () => {
  const body = gas.mcflyPayload(calendar, "ARMRA", new Date("2026-10-15T23:00:00Z"));
  const parsed = parseEvents(JSON.parse(JSON.stringify(body)));
  assert(!("error" in parsed), JSON.stringify(parsed));
  if ("error" in parsed) return;
  assertEquals(parsed.calendar, "ARMRA");
  assertEquals(parsed.replace, true);
  assertEquals(parsed.events.length, 5, "the declined event is left out");
  assertEquals(new Set(parsed.events.map((e) => e.id)).size, 5, "repeating instances get their own ids");
  const busy = parsed.events.find((e) => e.id!.startsWith("busy@"))!;
  assertEquals(busy.title, "Busy");
  assertEquals(parsed.events.every((e) => e.color === "#9FC6E7"), true);
  const trip = parsed.events.find((e) => e.id!.startsWith("trip@"))!;
  assertEquals(trip.location!.length, 300);
});

Deno.test("all-day events land on their own days on a Central-time display", () => {
  const body = gas.mcflyPayload(calendar, null, new Date("2026-10-15T23:00:00Z"));
  const parsed = parseEvents(JSON.parse(JSON.stringify(body)));
  if ("error" in parsed) throw new Error(parsed.error);
  const offsite = parsed.events.find((e) => e.id!.startsWith("offsite@"))!;
  const trip = parsed.events.find((e) => e.id!.startsWith("trip@"))!;
  // The display reads the stored UTC instant in local time and takes the date.
  assertEquals([chicagoDay(offsite.starts_at), chicagoDay(offsite.ends_at!)], ["2026-10-20", "2026-10-20"]);
  assertEquals([chicagoDay(trip.starts_at), chicagoDay(trip.ends_at!)], ["2026-10-31", "2026-11-02"]);
  assertEquals(body.events.find((e: { id: string }) => e.id.startsWith("trip@")).ends_at, "2026-11-02T23:59:59-06:00", "after DST the offset is -06:00");
  assertEquals(body.calendar, "ARMRA", "the calendar's own name by default");
});

Deno.test("pushToMcFly sends the key as a bearer token to the events feed", () => {
  gas.pushToMcFly();
  assert(fetched);
  assertEquals(fetched!.url, "https://uxvzhlkvbrwjlwxylkdd.supabase.co/functions/v1/ingest/events");
  assertEquals((fetched!.opts.headers as Record<string, string>).Authorization, "Bearer mcf_test");
  assertEquals(fetched!.opts.method, "post");
  const sent = JSON.parse(fetched!.opts.payload as string);
  assertEquals(sent.replace, true);
  assertEquals(sent.events.length, 5);
});

Deno.test("an all-day end date that comes back inclusive still parses", () => {
  const sameDay = { ...ev({ id: "x@google.com", title: "Holiday", allDay: ["2026-10-22", "2026-10-23"] }),
    getAllDayEndDate: () => localMidnight("2026-10-22") };
  const body = gas.mcflyPayload({ ...calendar, getEvents: () => [sameDay] }, "ARMRA", new Date("2026-10-15T23:00:00Z"));
  const parsed = parseEvents(JSON.parse(JSON.stringify(body)));
  if ("error" in parsed) throw new Error(parsed.error);
  assertEquals([chicagoDay(parsed.events[0].starts_at), chicagoDay(parsed.events[0].ends_at!)], ["2026-10-22", "2026-10-22"]);
});

Deno.test("a missing key or calendar id says how to fix it", () => {
  delete props.MCFLY_KEY;
  let msg = "";
  try { gas.pushToMcFly(); } catch (e) { msg = (e as Error).message; }
  assert(msg.includes("MCFLY_KEY"), msg);
});
