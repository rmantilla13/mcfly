import { assertEquals } from "jsr:@std/assert@1";
import { askQuery, eventDays, hasScope, parseMemoryPush, readRoute } from "./reads.ts";

Deno.test("read routes", () => {
  assertEquals(readRoute("/functions/v1/ingest/memory"), "memory");
  assertEquals(readRoute("/ingest/events"), "events");
  assertEquals(readRoute("/functions/v1/ingest/asks"), "asks");
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

Deno.test("which asks to read back", () => {
  assertEquals(askQuery(""), { ids: null, open_only: false });
  assertEquals(askQuery("?id=ship-2.3,headline&id=%20x%20"), { ids: ["ship-2.3", "headline", "x"], open_only: false });
  assertEquals(askQuery("?open=1"), { ids: null, open_only: true });
  assertEquals(askQuery(`?id=${"a,".repeat(80)}`).ids?.length, 50);
  // An id param that leaves no id reads none, not the last 100.
  assertEquals(askQuery("?open=true&id="), { ids: [], open_only: true });
  assertEquals(askQuery("?id=%20,%20"), { ids: [], open_only: false });
  // A long id is cut to 200 characters, as a push cuts it, not dropped.
  assertEquals(askQuery(`?id=${"i".repeat(250)}`).ids, ["i".repeat(200)]);
  assertEquals(askQuery(`?id=%20${"i".repeat(250)}%20,b`).ids, ["i".repeat(200), "b"]);
});
