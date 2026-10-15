// The Ask panel's stream reader (lib/sse.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { splitEvents } from "../lib/sse.ts";

test("complete events out, the partial one kept", () => {
  const { events, rest } = splitEvents('event: delta\ndata: {"text":"Hi"}\n\nevent: delta\ndata: {"te');
  assert.deepEqual(events, [{ event: "delta", data: '{"text":"Hi"}' }]);
  assert.equal(rest, 'event: delta\ndata: {"te');
  const next = splitEvents(rest + 'xt":" there"}\n\nevent: done\ndata: {}\n\n');
  assert.deepEqual(next.events.map((e) => e.event), ["delta", "done"]);
  assert.equal(next.rest, "");
});

test("CRLF, default event name, multi-line data", () => {
  const { events } = splitEvents("data: a\r\ndata: b\r\n\r\n");
  assert.deepEqual(events, [{ event: "message", data: "a\nb" }]);
});
