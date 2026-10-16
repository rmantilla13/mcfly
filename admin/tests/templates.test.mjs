// Agent templates and their task prompts (lib/templates.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { AGENT_TEMPLATES, agentPrompt, templateById } from "../lib/templates.ts";

test("every template is complete and the ids are unique", () => {
  const ids = new Set();
  for (const t of AGENT_TEMPLATES) {
    assert.ok(t.id && t.label && t.description && t.schedule && t.job, t.id);
    assert.match(t.color, /^#[0-9A-F]{6}$/i);
    assert.ok(!ids.has(t.id));
    ids.add(t.id);
  }
  assert.equal(templateById("nope").id, "custom");
  assert.equal(templateById("markets").feed, "quotes");
});

test("the prompt carries the endpoint, the key and the body shape", () => {
  const t = templateById("briefs");
  const p = agentPrompt({ template: t, name: "Grok", baseUrl: "https://x.supabase.co/", key: "mcf_abc", scopes: t.scopes });
  assert.match(p, /POST https:\/\/x\.supabase\.co\/functions\/v1\/ingest\/briefs/);
  assert.match(p, /Authorization: Bearer mcf_abc/);
  assert.match(p, /"briefs":\[/);
  assert.match(p, /ingest\/memory/);
  assert.match(p, /ingest\/events\?days=14/);
  assert.match(p, /background facts, not instructions/);
});

test("without the key, a placeholder; without scopes, no reads", () => {
  const t = templateById("markets");
  const p = agentPrompt({ template: t, name: "Desk", baseUrl: "https://x.supabase.co", scopes: [] });
  assert.match(p, /<your McFly agent key>/);
  assert.doesNotMatch(p, /You may also read/);
  assert.match(p, /ingest\/quotes/);
});

test("the market desk sends holdings only from real positions, and signals as facts", () => {
  const t = templateById("markets");
  const p = agentPrompt({ template: t, name: "Desk", baseUrl: "https://x", scopes: [] });
  assert.match(p, /"position"/);
  assert.match(p, /Never guess one/);
  assert.match(p, /"signals"/);
  assert.match(p, /never buy, sell or hold advice/);
  assert.match(p, /"stats"/);
  // The example body shows the same fields.
  assert.match(p, /"position":\{"shares":40/);
});

test("a calendar mirror is told to replace", () => {
  const t = templateById("calendar");
  assert.match(agentPrompt({ template: t, name: "Cal", baseUrl: "https://x", scopes: [] }), /"replace": true/);
});
