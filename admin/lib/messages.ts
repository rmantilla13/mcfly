// The household thread (the messages table, migration 20261103000010): the
// people at home write on a display, the person replies from here, the app
// or the phone's notification. The page reads the thread once, then polls
// what changed; these are the pure parts, so tests/messages.test.mjs can
// check them.

export type Message = {
  id: string;
  sender_kind: "display" | "person";
  sender_name: string;
  body: string;
  device_id: string | null;
  via: string;
  created_at: string;
  updated_at: string;
  read_at: string | null;
  notified_at: string | null;
  notify_error: string | null;
  // A voice note (migration 20261104000020): its WAV in voice-notes, and how long.
  audio_path?: string | null;
  audio_ms?: number | null;
};

export type MessageNames = { household: string[]; mine: string | null };

// Away mode (platform_settings.away_*, migration 20261104000010): away from
// `since` until `until` (null: until it's turned off), decided against the
// clock, so it ends on time without a write.
export type AwayStatus = { since: string | null; until: string | null; note: string | null; name: string | null };
export const NOT_AWAY: AwayStatus = { since: null, until: null, note: null, name: null };

export function isAway(away: AwayStatus, nowMs: number): boolean {
  return away.since != null && (away.until == null || Date.parse(away.until) > nowMs);
}

// "Away until 6:00 PM", "Away until Thursday 9:00 AM", "Away", or "Home".
export function awayLabel(away: AwayStatus, nowMs: number, timeZone?: string): string {
  if (!isAway(away, nowMs)) return "Home";
  if (!away.until) return "Away";
  const until = Date.parse(away.until);
  const time = new Date(until).toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit", timeZone });
  const day = (t: number) => new Date(t).toLocaleDateString("en-CA", { timeZone });
  if (day(until) === day(nowMs)) return `Away until ${time}`;
  return `Away until ${new Date(until).toLocaleDateString("en-US", { weekday: "long", timeZone })} ${time}`;
}

// The "back" choice from the console's form: "" (when it's turned off) or a
// number of hours, as an instant from `nowMs`; anything else is null.
export function awayUntil(choice: string, nowMs: number): string | null {
  const hours = Number(choice);
  if (!choice || !Number.isInteger(hours) || hours < 1 || hours > 24) return null;
  return new Date(nowMs + hours * 3_600_000).toISOString();
}

export const MESSAGE_COLUMNS = "id,sender_kind,sender_name,body,device_id,via,created_at,updated_at,read_at,notified_at,notify_error,audio_path,audio_ms";
// A voice note's path, as send_message makes them: <auth user>/<uuid>.wav.
export const VOICE_NOTE_PATH = /^[0-9a-f-]{36}\/[0-9a-f-]{36}\.wav$/;

// "0:12".
export function noteClock(ms: number): string {
  const seconds = Math.round(ms / 1000);
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

// What a voice note says without a caption, as send_message writes it.
export const voiceNoteLabel = (ms: number) => `🎤 Voice note · ${noteClock(ms)}`;

export const hasAudio = (m: Message) => !!m.audio_path && (m.audio_ms ?? 0) > 0;

// A message's words: for a voice note, "" when they're the server's own label.
export function caption(m: Message): string {
  if (!hasAudio(m)) return m.body;
  return m.body === voiceNoteLabel(m.audio_ms ?? 0) ? "" : m.body;
}
export const MAX_MESSAGE = 500;
// Each poll looks this far behind the newest change it has, so a message
// that committed late isn't missed.
export const OVERLAP_MS = 30_000;

const order = (a: Message, b: Message) => a.created_at.localeCompare(b.created_at) || a.id.localeCompare(b.id);
const ms = (iso: string | null) => (iso ? Date.parse(iso) : NaN);

// Rows in: a known one is replaced when the server's copy is newer, or the
// same copy brings no read that this page already marked; oldest first,
// the newest `keep` kept.
export function mergeMessages(known: Message[], rows: Message[], keep = 200): Message[] {
  const byId = new Map(known.map((m) => [m.id, m]));
  for (const row of rows) {
    const had = byId.get(row.id);
    if (had) {
      const a = ms(had.updated_at), b = ms(row.updated_at);
      if (a > b) continue;
      if (a === b && had.read_at && !row.read_at) continue;
    }
    byId.set(row.id, row);
  }
  return [...byId.values()].sort(order).slice(-keep);
}

// The newest updated_at among `messages`, for the next poll (less the overlap).
export function pollSince(messages: Message[]): string | null {
  let newest = NaN;
  for (const m of messages) newest = Math.max(Number.isNaN(newest) ? -Infinity : newest, ms(m.updated_at));
  return Number.isFinite(newest) ? new Date(newest - OVERLAP_MS).toISOString() : null;
}

// From home and not read yet.
export const unreadFromHome = (messages: Message[]) => messages.filter((m) => m.sender_kind === "display" && !m.read_at);

// Whether a message starts a run: the first, a different writer from the one
// before, or ten minutes or more after it. A run shows its writer once.
export function startsRun(m: Message, previous: Message | undefined): boolean {
  if (!previous) return true;
  return (
    previous.sender_kind !== m.sender_kind || previous.sender_name !== m.sender_name || ms(m.created_at) - ms(previous.created_at) >= 600_000
  );
}

// A day's heading in the account's time zone: Today, Yesterday, the weekday
// within a week, else the date.
export function dayHeading(iso: string, nowMs: number, timeZone?: string): string {
  const key = (t: number) => new Date(t).toLocaleDateString("en-CA", { timeZone });
  const day = key(ms(iso));
  if (day === key(nowMs)) return "Today";
  if (day === key(nowMs - 86_400_000)) return "Yesterday";
  const days = (Date.parse(key(nowMs)) - Date.parse(day)) / 86_400_000;
  if (days > 0 && days < 7) return new Date(ms(iso)).toLocaleDateString("en-US", { weekday: "long", timeZone });
  const sameYear = day.slice(0, 4) === key(nowMs).slice(0, 4);
  return new Date(ms(iso)).toLocaleDateString("en-US", { month: "short", day: "numeric", ...(sameYear ? {} : { year: "numeric" }), timeZone });
}

// The thread by day, each message marked where a run starts.
export function threadDays(messages: Message[], nowMs: number, timeZone?: string) {
  const days: { title: string; items: { message: Message; runStart: boolean }[] }[] = [];
  let previous: Message | undefined;
  for (const m of [...messages].sort(order)) {
    const title = dayHeading(m.created_at, nowMs, timeZone);
    if (days.at(-1)?.title !== title) {
      days.push({ title, items: [] });
      previous = undefined;
    }
    days.at(-1)!.items.push({ message: m, runStart: startsRun(m, previous) });
    previous = m;
  }
  return days;
}

// Under the person's newest reply: whether home has seen it.
export const replyStatus = (m: Message) => (m.read_at ? "Seen at home" : "Sent");

// Under a message from home: whether its notification went, and why not.
export function notifyNote(m: Message): string | null {
  if (m.sender_kind !== "display") return null;
  if (m.notified_at) return null;
  return m.notify_error ? `No notification: ${m.notify_error}` : null;
}

// The names typed into the console's field, one a line or comma: trimmed,
// blanks and repeats (any case) left out. The database checks them again.
export function parseNames(text: string): string[] {
  const out: string[] = [];
  for (const raw of text.split(/[\n,]/)) {
    const name = raw.trim();
    if (name && !out.some((n) => n.toLowerCase() === name.toLowerCase())) out.push(name);
  }
  return out;
}

// The demo's thread: two at home today and the person's replies.
export function demoMessages(nowMs: number): Message[] {
  const at = (minutes: number) => new Date(nowMs - minutes * 60_000).toISOString();
  const m = (id: number, kind: Message["sender_kind"], name: string, body: string, minutes: number, extra: Partial<Message> = {}): Message => ({
    id: `6d000000-0000-0000-0000-00000000000${id}`,
    sender_kind: kind,
    sender_name: name,
    body,
    device_id: null,
    via: kind === "display" ? "display" : "app",
    created_at: at(minutes),
    updated_at: at(minutes),
    read_at: null,
    notified_at: kind === "display" ? at(minutes) : null,
    notify_error: null,
    ...extra,
  });
  return [
    m(1, "display", "Mia", "I'm home from school!", 185, { read_at: at(180) }),
    m(2, "person", "Parent", "Yay! Snack is in the fridge. Homework first 🙂", 178, { read_at: at(176) }),
    m(3, "display", "Leo", "Can Sam come over to play?", 24),
    m(5, "display", "Leo", voiceNoteLabel(6400), 23, { audio_path: "demo/leo.wav", audio_ms: 6400 }),
    m(4, "display", "Mia", "When are you coming home?", 6),
  ];
}
