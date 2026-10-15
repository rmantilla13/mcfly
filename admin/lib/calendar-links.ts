// Google's "Public address in iCal format" only works for a public calendar;
// for a private one Google answers 404. The add form warns when one is pasted
// (holiday and other public calendars are fine, so it never refuses).
export function isGooglePublicAddress(link: string): boolean {
  try {
    const u = new URL(link.trim().replace(/^webcal:\/\//i, "https://"));
    return u.hostname.toLowerCase() === "calendar.google.com" && u.pathname.includes("/public/");
  } catch {
    return false;
  }
}
