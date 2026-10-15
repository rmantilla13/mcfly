// Reading back through ingest, for agents the admin has given scopes:
//
//   GET  /ingest/memory   (memory:read)   the shared notes and the agent's own
//   POST /ingest/memory   (memory:write)  { memories: [{ key?, text, shared? }], remove?: [key] }
//   GET  /ingest/events   (calendar:read) upcoming events; ?days=1..60 (default 14)
//
// Pure, so reads.test.ts can check it.

export type Scope = "memory:read" | "memory:write" | "calendar:read";

export type MemoryPush = { items: { key?: string; text: string; shared?: boolean }[]; remove: string[] };

const KEY = /^[A-Za-z0-9._:-]{1,80}$/;

export function readRoute(pathname: string): "memory" | "events" | null {
  const parts = pathname.split("/").filter(Boolean);
  const at = parts.lastIndexOf("ingest");
  const rest = at < 0 ? parts : parts.slice(at + 1);
  if (rest.length !== 1) return null;
  return rest[0] === "memory" ? "memory" : rest[0] === "events" ? "events" : null;
}

export function hasScope(scopes: unknown, scope: Scope): boolean {
  return Array.isArray(scopes) && scopes.includes(scope);
}

export function scopeMissing(scope: Scope): string {
  return `this agent doesn't have ${scope}; an admin can grant it on the console's Agents page`;
}

export function parseMemoryPush(body: unknown): MemoryPush | { error: string } {
  if (typeof body !== "object" || body === null || Array.isArray(body)) return { error: "send { memories: [...] }" };
  const b = body as Record<string, unknown>;
  const list = b.memories ?? [];
  const remove = b.remove ?? [];
  if (!Array.isArray(list)) return { error: "memories must be a list" };
  if (!Array.isArray(remove)) return { error: "remove must be a list of keys" };
  if (list.length === 0 && remove.length === 0) return { error: "nothing to write: add memories or remove" };
  if (list.length > 50) return { error: "at most 50 notes per push" };
  const items: MemoryPush["items"] = [];
  for (const [i, raw] of list.entries()) {
    if (typeof raw === "string") {
      if (!raw.trim()) return { error: `memories[${i}] is empty` };
      items.push({ text: raw.trim().slice(0, 2000) });
      continue;
    }
    if (typeof raw !== "object" || raw === null) return { error: `memories[${i}] must be text or { key?, text, shared? }` };
    const m = raw as Record<string, unknown>;
    if (typeof m.text !== "string" || !m.text.trim()) return { error: `memories[${i}].text is required` };
    if (m.text.trim().length > 2000) return { error: `memories[${i}].text is over 2000 characters` };
    if (m.key !== undefined && (typeof m.key !== "string" || !KEY.test(m.key))) {
      return { error: `memories[${i}].key must be 1 to 80 letters, digits, dots, colons, dashes or underscores` };
    }
    if (m.shared !== undefined && typeof m.shared !== "boolean") return { error: `memories[${i}].shared must be true or false` };
    items.push({ text: m.text.trim(), ...(m.key ? { key: m.key as string } : {}), ...(m.shared ? { shared: true } : {}) });
  }
  const keys: string[] = [];
  for (const [i, k] of remove.entries()) {
    if (typeof k !== "string" || !KEY.test(k)) return { error: `remove[${i}] must be a note key` };
    keys.push(k);
  }
  return { items, remove: keys };
}

export function eventDays(search: string): number {
  const n = Number(new URLSearchParams(search).get("days") ?? 14);
  return Number.isFinite(n) ? Math.min(60, Math.max(1, Math.round(n))) : 14;
}
