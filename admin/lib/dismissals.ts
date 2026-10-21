// What's been dismissed (the dismissals table, migration 20261021000070):
// an insight's id, lower-cased (`blocked:<project id>`, `metric:<key>`, …),
// and when it runs out (null: when the project changes, which the server
// sees to). The display and the app hide the same ids. Pure, so
// tests/dismissals.test.mjs can check it.

export type Dismissal = { key: string; hide_until: string | null };

// Whether `id` (any case) has a dismissal that hasn't run out at `nowMs`.
export function isDismissed(dismissals: Dismissal[], id: string, nowMs: number): boolean {
  const key = id.trim().toLowerCase();
  return dismissals.some((d) => d.key === key && (d.hide_until == null || Date.parse(d.hide_until) > nowMs));
}
