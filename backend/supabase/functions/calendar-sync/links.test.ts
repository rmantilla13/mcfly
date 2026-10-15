import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { refusedMessage } from "./links.ts";

const google = "https://calendar.google.com/calendar/ical";

Deno.test("a Google public address points to the secret one", () => {
  const msg = refusedMessage(`${google}/team%40example.com/public/basic.ics`, 404);
  assertStringIncludes(msg, "Google answered 404");
  assertStringIncludes(msg, "public address");
  assertStringIncludes(msg, "Secret address in iCal format");
});

Deno.test("a Google secret address that stopped working was reset", () => {
  const msg = refusedMessage(`${google}/me%40example.com/private-0123456789abcdef/basic.ics`, 404);
  assertStringIncludes(msg, "was reset");
  assertStringIncludes(msg, "Secret address in iCal format again");
});

Deno.test("other hosts get the general sentence", () => {
  assertEquals(refusedMessage("https://p12-caldav.icloud.com/published/2/abc", 403),
    "the link answered 403; it may have been reset, or the calendar isn't shared");
});

Deno.test("an unparseable link still gets a sentence", () => {
  assertEquals(refusedMessage("not a url", 401), "the link answered 401; it may have been reset, or the calendar isn't shared");
});

Deno.test("messages fit the 300 characters calendar_source_synced keeps", () => {
  for (const path of ["public", "private-abc"]) {
    const msg = refusedMessage(`${google}/x%40example.com/${path}/basic.ics`, 404);
    assertEquals(msg.length <= 300, true, `${msg.length} characters`);
  }
});
