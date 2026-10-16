// The display's time of day, for the console: the same four moods on the
// same clock (display/src/hardware/DisplayController.cpp: night from 21:30 to
// 6:30, then morning until 11, day until 17, evening after), and the glow
// each mood paints with (display/qml/Theme.qml's glow arrays). MOOD_SCRIPT
// puts the mood on <html> as data-mood before the first paint, MoodProvider
// keeps it current, and globals.css swaps --glow-1..3 to these colours;
// tests/mood.test.mjs keeps all three in step. Pure, so the test can load it.

export type Mood = "morning" | "day" | "evening" | "night";

export const MOODS: readonly Mood[] = ["morning", "day", "evening", "night"];

// Blue, coral and amber by day; the first three of each Theme.qml glow array
// otherwise. Day is the console's own --glow-1..3.
export const MOOD_GLOW: Readonly<Record<Mood, readonly [string, string, string]>> = {
  morning: ["#f6b94a", "#f07f5a", "#f2a7c3"],
  day: ["#5b7cf5", "#f07f5a", "#f6b94a"],
  evening: ["#7a64e8", "#e86a92", "#f07f5a"],
  night: ["#3b4fb8", "#7a64e8", "#a04e78"],
};

const NIGHT_START = 21 * 60 + 30;
const NIGHT_END = 6 * 60 + 30;
const MORNING_END = 11 * 60;
const DAY_END = 17 * 60;

// One formatter per zone: the ambient view asks every second.
const formatters = new Map<string, Intl.DateTimeFormat>();

function formatter(timeZone: string | undefined): Intl.DateTimeFormat {
  const key = timeZone ?? "";
  let f = formatters.get(key);
  if (!f) {
    try {
      f = new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric", minute: "numeric", hourCycle: "h23" });
    } catch {
      // Not a zone this runtime knows: the runtime's own, rather than a throw.
      f = new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "numeric", hourCycle: "h23" });
    }
    formatters.set(key, f);
  }
  return f;
}

// Minutes since local midnight in `timeZone` (the runtime's zone if absent).
export function minuteOfDay(ms: number, timeZone?: string): number {
  let hour = 0;
  let minute = 0;
  for (const p of formatter(timeZone).formatToParts(new Date(ms))) {
    if (p.type === "hour") hour = Number(p.value) % 24;
    else if (p.type === "minute") minute = Number(p.value);
  }
  return hour * 60 + minute;
}

export function isNight(ms: number, timeZone?: string): boolean {
  const m = minuteOfDay(ms, timeZone);
  return m >= NIGHT_START || m < NIGHT_END;
}

export function moodAt(ms: number, timeZone?: string): Mood {
  const m = minuteOfDay(ms, timeZone);
  if (m >= NIGHT_START || m < NIGHT_END) return "night";
  if (m < MORNING_END) return "morning";
  if (m < DAY_END) return "day";
  return "evening";
}

// moodAt in the browser's zone as an inline script, for the root layout to
// run before the first paint: without it a page opened outside 11:00-17:00
// paints the day glow, then turns once React has hydrated. Built from the
// same constants, and the test runs it against moodAt minute by minute.
export const MOOD_SCRIPT =
  "try{var d=new Date(),m=d.getHours()*60+d.getMinutes();" +
  `document.documentElement.dataset.mood=m>=${NIGHT_START}||m<${NIGHT_END}?"night":m<${MORNING_END}?"morning":m<${DAY_END}?"day":"evening"}catch(e){}`;
