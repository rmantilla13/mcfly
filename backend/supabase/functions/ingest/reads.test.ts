import { assertEquals } from "jsr:@std/assert@1";
import { eventDays, hasScope, parseMemoryPush, readRoute } from "./reads.ts";

Deno.test("read routes", () => {
  assertEquals(readRoute("/functions/v1/ingest/memory"), "memory");
  assertEquals(readRoute("/ingest/events"), "events");
  assertEquals(readRoute("/ingest/briefs"), null);
  assertEquals(readRoute("/ingest"), null);
  assertEquals(readRoute("/ingest/memory/x"), null);
});

Deno.test("scopes", () => {
  assertEquals(hasScope(["memory:read"], "memory:read"), true);
  assertEquals(hasScope(["memory:read"], "memory:write"), false);
  assertEquals(hasScope(null, "calendar:read"), false);
});

Deno.test("memory pushes", () => {
  assertEquals(parseMemoryPush({ memories: ["  Likes F1 ", { key: "tone", text: "Short." }, { text: "Shared", shared: true }] }), {
    items: [{ text: "Likes F1" }, { key: "tone", text: "Short." }, { text: "Shared", shared: true }],
    remove: [],
  });
  assertEquals(parseMemoryPush({ remove: ["tone"] }), { items: [], remove: ["tone"] });
  assertEquals("error" in parseMemoryPush({}), true);
  assertEquals("error" in parseMemoryPush({ memories: [{ text: "" }] }), true);
  assertEquals("error" in parseMemoryPush({ memories: [{ key: "bad key", text: "x" }] }), true);
  assertEquals("error" in parseMemoryPush({ memories: [{ text: "x", shared: "yes" }] }), true);
  assertEquals("error" in parseMemoryPush({ remove: [1] }), true);
  assertEquals("error" in parseMemoryPush({ memories: Array(51).fill("x") }), true);
  assertEquals("error" in parseMemoryPush([]), true);
});

Deno.test("event window", () => {
  assertEquals(eventDays(""), 14);
  assertEquals(eventDays("?days=3"), 3);
  assertEquals(eventDays("?days=999"), 60);
  assertEquals(eventDays("?days=0"), 1);
  assertEquals(eventDays("?days=x"), 14);
});
