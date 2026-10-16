// Weather over the ambient view's backdrop, as the display draws it over its
// savers' (display/qml/components/Weather.qml): snow, petals, fireflies or
// leaves, the display's choice under Displays → Customize. "season" picks by
// the date and the hemisphere of the account's time zone, where the display
// is. Which kind, which season and how many are DisplayController's rules
// (weatherFor, seasonFor, southernZone, weatherCount) and the app's, kept
// the same by tests/weather.test.mjs; the motion is this file's.

export const WEATHERS = ["off", "season", "snow", "petals", "fireflies", "leaves"] as const;
export type WeatherPref = (typeof WEATHERS)[number];
export type WeatherKind = "snow" | "petals" | "fireflies" | "leaves";
export type Season = "winter" | "spring" | "summer" | "autumn";

const KIND_FOR: Record<Season, WeatherKind> = { winter: "snow", spring: "petals", summer: "fireflies", autumn: "leaves" };
export const WEATHER_NAMES: Record<WeatherKind, string> = { snow: "Snow", petals: "Petals", fireflies: "Fireflies", leaves: "Leaves" };

/** A saved setting, or off for anything this build doesn't know. */
export function parseWeather(value: unknown): WeatherPref {
  return (WEATHERS as readonly unknown[]).includes(value) ? (value as WeatherPref) : "off";
}

// Meteorological seasons, whole months, as the north has them: December to
// February is winter.
const NORTH: Season[] = ["winter", "winter", "spring", "spring", "spring", "summer", "summer", "summer", "autumn", "autumn", "autumn", "winter"];

/** The season in month `month` (1–12), in the north or six months on in the south. */
export function seasonFor(month: number, south: boolean): Season {
  const m = month - 1;
  return NORTH[south ? (m + 6) % 12 : m];
}

// Time zones south of the equator: a whole region by prefix where every
// zone in it is, one by one elsewhere. One missing gets the north's seasons.
const SOUTH_PREFIXES = ["Australia/", "Antarctica/", "America/Argentina/", "Chile/", "Brazil/"];
const SOUTH_ZONES = new Set([
  "NZ", "NZ-CHAT", "Pacific/Auckland", "Pacific/Chatham", "Pacific/Fiji", "Pacific/Noumea", "Pacific/Tongatapu",
  "Pacific/Apia", "Pacific/Efate", "Pacific/Norfolk", "Pacific/Tahiti", "Pacific/Easter", "Pacific/Rarotonga",
  "America/Santiago", "America/Punta_Arenas", "America/Montevideo", "America/Asuncion", "America/Sao_Paulo",
  "America/La_Paz", "America/Lima", "America/Recife", "America/Bahia", "America/Maceio", "America/Cuiaba",
  "America/Campo_Grande", "America/Porto_Velho", "America/Rio_Branco",
  "Atlantic/Stanley", "Atlantic/South_Georgia", "Atlantic/St_Helena",
  "Africa/Johannesburg", "Africa/Maputo", "Africa/Harare", "Africa/Lusaka", "Africa/Windhoek", "Africa/Gaborone",
  "Africa/Maseru", "Africa/Mbabane", "Africa/Blantyre", "Africa/Lubumbashi", "Africa/Luanda", "Africa/Dar_es_Salaam",
  "Indian/Antananarivo", "Indian/Mauritius", "Indian/Reunion", "Indian/Mayotte", "Indian/Comoro",
]);

/** Whether an IANA time zone is south of the equator. */
export function southernZone(zone: string | null | undefined): boolean {
  const tz = zone ?? "";
  return SOUTH_ZONES.has(tz) || SOUTH_PREFIXES.some((p) => tz.startsWith(p));
}

/** The month (1–12) at `ms` in `timeZone`. */
function monthIn(ms: number, timeZone: string): number {
  try {
    return Number(new Intl.DateTimeFormat("en-US", { month: "numeric", timeZone }).format(new Date(ms)));
  } catch {
    return new Date(ms).getUTCMonth() + 1;
  }
}

/** What falls at `ms` where `timeZone` is: a kind, or null while off. */
export function weatherFor(pref: WeatherPref, ms: number, timeZone: string): WeatherKind | null {
  if (pref === "season") return KIND_FOR[seasonFor(monthIn(ms, timeZone), southernZone(timeZone))];
  return pref === "off" ? null : pref;
}

// How many: one per this many square pixels, within bounds. A phone gets a
// few; a big screen is not crowded, nor paying for a crowd.
const DENSITY: Record<WeatherKind, { per: number; min: number; max: number }> = {
  snow: { per: 26_000, min: 12, max: 44 },
  petals: { per: 60_000, min: 6, max: 18 },
  leaves: { per: 85_000, min: 5, max: 14 },
  fireflies: { per: 65_000, min: 7, max: 20 },
};

/** How many of `kind` a screen width × height shows at once. */
export function weatherCount(kind: string, width: number, height: number): number {
  const d = DENSITY[kind as WeatherKind];
  if (!d) return 0;
  const n = Math.round((Math.max(0, width) * Math.max(0, height)) / d.per);
  return Math.max(d.min, Math.min(d.max, n));
}

/** The kinds that fall through the screen (and so leave it); fireflies wander in it. */
export const falls = (kind: WeatherKind) => kind !== "fireflies";

type WeatherDevice = { settings?: { weather?: string | null } | null; last_seen_at?: string | null; created_at: string };

/** The weather of the display seen last (lib/sky.ts displayBackdrop picks the backdrop the same way). */
export function displayWeather(devices: readonly WeatherDevice[]): WeatherPref {
  const seen = (d: WeatherDevice) => Date.parse(d.last_seen_at ?? "") || 0;
  const latest = [...devices].sort((a, b) => seen(b) - seen(a) || Date.parse(b.created_at) - Date.parse(a.created_at))[0];
  return parseWeather(latest?.settings?.weather);
}

// ---- The particles: each one's own size, place and pace, as numbers the
// stylesheet animates with (components/today/AmbientWeather.module.css).
// Lengths are px, x and drift vw, y vh, times s, angles deg. Every fall
// starts part-way through (a negative delay), so the screen opens with
// weather already falling. A petal's or leaf's tumble is `flipK`, the
// cosine of how far it turns over: how flat it looks at the far end of the
// turn, below zero once it shows its back (a scale, which the compositor
// animates; a rotation by a custom property it does not, in Safari).

export type Particle = {
  size: number;
  alpha: number;
  tone: number;
  x: number;
  drift: number;
  dur: number;
  delay: number;
  sway: number;
  swayDur: number;
  swayDelay: number;
  flipK: number;
  flipDur: number;
  flipDelay: number;
  spinFrom: number;
  spinTo: number;
  spinDur: number;
  spinDelay: number;
  xs: number[];
  ys: number[];
};

const round = (v: number, places = 2) => Math.round(v * 10 ** places) / 10 ** places;
const DEG = Math.PI / 180;

export function makeParticles(kind: WeatherKind, count: number, random: () => number = Math.random): Particle[] {
  const r = (lo: number, hi: number) => lo + random() * (hi - lo);
  const wind = random() < 0.5 ? -1 : 1; // one wind for the whole scene
  const out: Particle[] = [];
  for (let i = 0; i < count; i++) {
    const p: Particle = {
      size: 0, alpha: 1, tone: 0, x: 0, drift: 0, dur: 0, delay: 0, sway: 0, swayDur: 1, swayDelay: 0,
      flipK: 1, flipDur: 1, flipDelay: 0, spinFrom: 0, spinTo: 0, spinDur: 1, spinDelay: 0, xs: [], ys: [],
    };
    if (kind === "fireflies") {
      // Four stops in the lower part of the screen, each a short hop from the last.
      const xs = [r(3, 97)];
      const ys = [r(35, 92)];
      for (let k = 1; k < 4; k++) {
        xs.push(Math.max(2, Math.min(98, xs[k - 1] + r(-22, 22))));
        ys.push(Math.max(30, Math.min(95, ys[k - 1] + r(-18, 18))));
      }
      p.size = round(r(28, 48));
      p.tone = 1 + Math.floor(random() * 2);
      p.xs = xs.map((v) => round(v));
      p.ys = ys.map((v) => round(v));
      p.dur = round(r(16, 30));
      p.delay = round(-r(0, p.dur));
      p.swayDur = round(r(2.2, 5.2)); // the glow's pulse
      p.swayDelay = round(-r(0, p.swayDur));
      out.push(p);
      continue;
    }
    if (kind === "snow") {
      // Nearer flakes are bigger, brighter, faster and sway further.
      const z = random();
      p.size = round(4 + z * 8);
      p.alpha = round(0.45 + z * 0.5);
      p.dur = round(24 - z * 12);
      p.drift = round(wind * r(0, 6));
      p.sway = round(4 + z * 16);
    } else if (kind === "petals") {
      p.size = round(r(20, 32));
      p.alpha = round(r(0.8, 0.95));
      p.tone = 1 + Math.floor(random() * 3);
      p.dur = round(r(18, 28));
      p.drift = round(wind * r(14, 34));
      p.sway = round(r(20, 50));
      p.flipK = round(Math.cos(r(50, 160) * DEG));
      const from = r(0, 360);
      p.spinFrom = round(from);
      p.spinTo = round(from + (random() < 0.5 ? -1 : 1) * r(180, 540));
      p.spinDur = round(r(5, 11));
      p.spinDelay = round(-r(0, p.spinDur));
    } else {
      // A leaf rocks like a pendulum: its swing and its tilt keep time.
      p.size = round(r(30, 48));
      p.alpha = round(r(0.85, 0.97));
      p.tone = 1 + Math.floor(random() * 4);
      p.dur = round(r(14, 22));
      p.drift = round(wind * r(4, 18));
      p.sway = round(r(36, 90));
      p.flipK = round(Math.cos(r(30, 110) * DEG));
      const tilt = r(25, 60);
      const base = r(0, 360);
      p.spinFrom = round(base - tilt);
      p.spinTo = round(base + tilt);
    }
    p.x = round(kind === "petals" && wind < 0 ? r(15, 125) : kind === "petals" ? r(-25, 85) : r(-6, 100));
    p.delay = round(-r(0, p.dur));
    p.swayDur = round(kind === "snow" ? r(2.2, 4.6) : kind === "petals" ? r(2.6, 5) : r(2.4, 4.2));
    p.swayDelay = round(-r(0, p.swayDur));
    if (kind === "leaves") {
      p.spinDur = p.swayDur;
      p.spinDelay = p.swayDelay;
    }
    p.flipDur = round(r(1.8, 3.6));
    p.flipDelay = round(-r(0, p.flipDur));
    out.push(p);
  }
  return out;
}
