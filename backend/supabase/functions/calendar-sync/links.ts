// What to tell the person when a calendar link is refused (401, 403 or 404),
// in a sentence the console shows under the calendar. Google is most of
// these: its "Public address in iCal format" only works for a public
// calendar (a private one answers 404), and a "Secret address" stops
// working when it is reset.

export function refusedMessage(url: string, status: number): string {
  let host = "";
  let path = "";
  try {
    const u = new URL(url);
    host = u.hostname.toLowerCase();
    path = u.pathname;
  } catch {
    // Not a URL: fall through to the general sentence.
  }
  if (host === "calendar.google.com") {
    if (path.includes("/public/")) {
      return `Google answered ${status}: that's the calendar's public address, which only works for a public calendar. ` +
        "Use its Secret address in iCal format instead (Google Calendar → Settings → the calendar → Integrate calendar).";
    }
    if (path.includes("/private-")) {
      return `Google answered ${status}: this secret address was reset, or the calendar was deleted. ` +
        "Copy the Secret address in iCal format again (Google Calendar → Settings → the calendar → Integrate calendar).";
    }
  }
  return `the link answered ${status}; it may have been reset, or the calendar isn't shared`;
}
