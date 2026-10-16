// IANA zones offered by the settings form's datalist. The field is free
// text, so any zone Postgres knows still works; these are the suggestions.
export const COMMON_TIMEZONES = [
  "America/New_York",
  "America/Chicago",
  "America/Denver",
  "America/Phoenix",
  "America/Los_Angeles",
  "America/Anchorage",
  "Pacific/Honolulu",
  "America/Toronto",
  "America/Vancouver",
  "America/Mexico_City",
  "America/Bogota",
  "America/Sao_Paulo",
  "America/Argentina/Buenos_Aires",
  "Europe/London",
  "Europe/Dublin",
  "Europe/Lisbon",
  "Europe/Paris",
  "Europe/Berlin",
  "Europe/Madrid",
  "Europe/Rome",
  "Europe/Amsterdam",
  "Europe/Stockholm",
  "Europe/Warsaw",
  "Europe/Athens",
  "Europe/Istanbul",
  "Europe/Moscow",
  "Africa/Cairo",
  "Africa/Johannesburg",
  "Africa/Lagos",
  "Asia/Dubai",
  "Asia/Karachi",
  "Asia/Kolkata",
  "Asia/Bangkok",
  "Asia/Singapore",
  "Asia/Hong_Kong",
  "Asia/Shanghai",
  "Asia/Tokyo",
  "Asia/Seoul",
  "Australia/Perth",
  "Australia/Sydney",
  "Australia/Melbourne",
  "Pacific/Auckland",
  "UTC",
];

// Whether this runtime knows the zone. The database checks again against
// pg_timezone_names; this catches typos before the round trip.
export function knownTimeZone(name: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: name });
    return true;
  } catch {
    return false;
  }
}

// ───────────────────────── From where the browser is ─────────────────────────

// The lookup for a position: Open-Meteo (open-meteo.com: free, no key, no
// account; the Apple app asks it for Home's weather) answers the forecast
// endpoint with the zone of the coordinates when asked for `timezone=auto`,
// and no forecast at all when no variable is asked for. Two decimals (about a
// kilometre) is plenty to tell a zone apart and says less about where the
// person is.
export function timeZoneLookupUrl(latitude: number, longitude: number): string {
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) throw new RangeError("A position needs a latitude and a longitude.");
  return `https://api.open-meteo.com/v1/forecast?latitude=${latitude.toFixed(2)}&longitude=${longitude.toFixed(2)}&timezone=auto`;
}

// The zone in Open-Meteo's answer, when it is one this runtime knows.
export function parseTimeZoneLookup(answer: unknown): string | null {
  if (!answer || typeof answer !== "object") return null;
  const zone = (answer as { timezone?: unknown }).timezone;
  return typeof zone === "string" && zone !== "" && knownTimeZone(zone) ? zone : null;
}

// The IANA zone at a position, or an error with a sentence for the page.
export async function timeZoneAt(latitude: number, longitude: number, fetchImpl: typeof fetch = fetch): Promise<string> {
  const res = await fetchImpl(timeZoneLookupUrl(latitude, longitude), { cache: "no-store" }).catch(() => null);
  if (!res || !res.ok) throw new Error("The time zone lookup couldn't be reached. Type the zone instead.");
  const zone = parseTimeZoneLookup(await res.json().catch(() => null));
  if (!zone) throw new Error("No time zone is known for where you are. Type it instead.");
  return zone;
}

// What to say when the browser gives no position (GeolocationPositionError's
// code: 1 refused, 2 unavailable, 3 timed out).
export function locationErrorSentence(code: number): string {
  switch (code) {
    case 1:
      return "Location is off for this site. Allow it in the browser's site settings and try again.";
    case 3:
      return "Finding where you are took too long. Try again.";
    default:
      return "Your location couldn't be found.";
  }
}
