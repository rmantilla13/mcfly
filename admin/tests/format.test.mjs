// Run with `npm test` (Node 22+ strips the TypeScript types itself).
import assert from "node:assert/strict";
import { test } from "node:test";
import {
  changeDirection,
  cssColor,
  describeAction,
  formatChange,
  formatDate,
  formatDateTime,
  formatPrice,
  formatRelative,
  formatShortDate,
  isOnline,
  preview,
} from "../lib/format.ts";

test("cssColor passes hex colors through", () => {
  for (const c of ["#4F7CF7", "#abc", "#abcd", "#11223344", " #8E9CE6 "]) assert.equal(cssColor(c), c.trim());
});

test("cssColor refuses anything that would be more CSS", () => {
  const payloads = [
    "red;position:fixed;inset:0",
    "url(https://tracker.example/x.png)",
    "#fff;background-image:url(//x)",
    "expression(alert(1))",
    "var(--accent)",
    "red",
    "#12345",
    "",
    null,
    undefined,
    7,
  ];
  for (const p of payloads) assert.equal(cssColor(p), null, String(p));
});

test("formatRelative reads past and future times", () => {
  const now = Date.parse("2026-10-14T12:00:00Z");
  assert.equal(formatRelative("2026-10-14T11:59:30Z", now), "just now");
  assert.equal(formatRelative("2026-10-14T09:00:00Z", now), "3 hr. ago");
  assert.equal(formatRelative("2026-10-17T12:00:00Z", now), "in 3 days");
  assert.equal(formatRelative(null, now), "never");
});

test("dates Postgres can hold but JavaScript can't read don't throw", () => {
  for (const odd of ["infinity", "-infinity", "12345-01-01T00:00:00+00:00", "garbage"]) {
    assert.equal(formatRelative(odd), odd);
    assert.equal(formatDate(odd), odd);
    assert.equal(formatDateTime(odd), odd);
    assert.equal(formatShortDate(odd), odd);
  }
  assert.equal(formatDate("2026-10-06T23:30:00-02:00"), "Oct 7, 2026");
  assert.equal(formatShortDate("2026-10-14"), "Oct 14");
  assert.equal(formatDate(null), "—");
});

test("a display is online for 15 minutes after its check-in", () => {
  const now = Date.parse("2026-10-14T12:00:00Z");
  assert.equal(isOnline("2026-10-14T11:50:00Z", now), true);
  assert.equal(isOnline("2026-10-14T11:44:59Z", now), false);
  assert.equal(isOnline(null, now), false);
  assert.equal(isOnline("garbage", now), false);
});

test("preview flattens a brief's body to one line", () => {
  assert.equal(preview("Three things.\n\n- One.\n- Two."), "Three things. - One. - Two.");
  const long = preview("x".repeat(200));
  assert.equal(long.length, 161);
  assert.ok(long.endsWith("…"));
  assert.equal(preview("short"), "short");
});

test("prices and changes format for the markets table", () => {
  assert.equal(formatPrice(247.9, "USD"), "$247.90");
  assert.equal(formatPrice(1234.5, "EUR"), "€1,234.50");
  assert.equal(formatPrice(10, "zz"), "$10.00"); // not a currency code: dollars
  assert.equal(formatPrice(null, "USD"), "—");
  assert.equal(formatChange(2.78, 1.13), "+2.78 (+1.13%)");
  assert.equal(formatChange(-3.1, -1.62), "−3.10 (−1.62%)");
  assert.equal(formatChange(null, 0.5), "+0.50%");
  assert.equal(formatChange(0, null), "0.00");
  assert.equal(formatChange(null, null), "—");
  assert.equal(changeDirection(2, null), "up");
  assert.equal(changeDirection(null, -1), "down");
  assert.equal(changeDirection(0, 0), "flat");
});

test("describeAction knows every McFly audit action", () => {
  const actions = {
    create_agent: "Created agent",
    rotate_agent_key: "Rotated agent key",
    update_agent: "Updated agent",
    revoke_agent: "Revoked agent",
    delete_agent: "Deleted agent",
    delete_brief: "Deleted brief",
    delete_symbol: "Deleted symbol",
    delete_news_report: "Deleted news report",
    rename_device: "Renamed display",
    revoke_device: "Revoked display",
    pair_device: "Paired display",
    update_settings: "Updated settings",
  };
  for (const [action, words] of Object.entries(actions)) assert.equal(describeAction(action), words);
  assert.equal(describeAction("set_symbol", { hidden: true }), "Hid symbol");
  assert.equal(describeAction("set_symbol", { hidden: false }), "Showed symbol");
  assert.equal(describeAction("set_symbol", { sort_order: 2 }), "Reordered symbol");
  assert.equal(describeAction("set_symbol", {}), "Changed symbol");
  const more = {
    delete_project: "Deleted project",
    delete_metric: "Deleted metric",
    delete_dashboard: "Deleted dashboard",
    delete_event: "Deleted event",
    delete_calendar: "Removed calendar",
  };
  for (const [action, words] of Object.entries(more)) assert.equal(describeAction(action), words);
  assert.equal(describeAction("set_metric", { hidden: true }), "Hid metric");
  assert.equal(describeAction("set_metric", { label: "Sales", group_name: "Shop" }), "Relabeled metric");
  assert.equal(describeAction("set_metric", {}), "Changed metric");
  assert.equal(describeAction("set_dashboard", { hidden: false }), "Showed dashboard");
  assert.equal(describeAction("set_dashboard", { sort_order: 1 }), "Reordered dashboard");
  assert.equal(describeAction("set_admin", { make_admin: true }), "Made admin");
  assert.equal(describeAction("set_admin", { make_admin: false }), "Removed admin");
  assert.equal(describeAction("something_new"), "something new");
});
