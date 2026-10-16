// Holdings, signals and the day's numbers (lib/holdings.ts), as the display
// shapes them (display/tests/tst_feedstore.cpp: shapesHoldingsAndSignals,
// aHoldingCountsWhileInTheNewestPush).
import assert from "node:assert/strict";
import { test } from "node:test";
import { buildHoldings, compact, dataNumber, sharesLabel, signalsOf, signedPct, signedPrice } from "../lib/holdings.ts";

const NOW = "2026-10-16T14:00:00.000000+00:00";
const EARLIER = "2026-10-16T13:45:00.000000+00:00";

const quote = (symbol, price, change, as_of = NOW, extra = {}) => ({
  symbol, name: null, sort_order: 0, hidden: false, price, change, change_pct: null, currency: "USD", note: null, as_of,
  agent_name: "Market desk", agent_color: null, history_count: 1, ...extra,
});
const latest = (symbol, data, as_of = NOW, created_at = NOW) => ({ symbol, agent_id: "a2", as_of, created_at, data });

test("holdings, signals, stats and the total", () => {
  const aaa = {
    position: { shares: 4, avg_cost: 40 },
    signals: [{ text: "RSI 71, near the overbought line", tone: "up" }, "Earnings in 3 days", { text: "  ", tone: "down" }],
    stats: { open: 49, high: 51, low: 48.5, prev_close: 49, volume: 52300000, avg_volume: 41000000, market_cap: 3.7e12, pe: 37.24, low_52w: 30, high_52w: 60, earnings: "Oct 30, after close" },
  };
  const bbb = { position: { shares: "1.5", value: "150", day_change: -3 } };
  const { insights, portfolio } = buildHoldings([quote("AAA", 50, 1), quote("BBB", 100, -2)], [latest("AAA", aaa), latest("BBB", bbb)]);

  const a = insights.AAA.holding;
  assert.equal(a.value, 200); // 4 × $50
  assert.equal(a.dayChange, 4); // 4 × $1
  assert.equal(a.totalChange, 40); // $200 − 4 × $40
  assert.equal(a.totalChangePct, 25);
  assert.ok(Math.abs(a.weightPct - (200 / 350) * 100) < 1e-9);
  assert.deepEqual(insights.AAA.signals, [
    { text: "RSI 71, near the overbought line", tone: "up" },
    { text: "Earnings in 3 days", tone: "watch" },
  ]);
  assert.deepEqual(insights.AAA.stats.map((s) => `${s.label}=${s.value}`), [
    "Open=$49.00", "Prev close=$49.00", "Volume=52.3M · 1.3× avg", "Market cap=$3.7T", "P/E=37.2", "Earnings=Oct 30, after close",
  ]);
  assert.deepEqual(insights.AAA.ranges.map((r) => r.label), ["Today", "52 weeks"]);
  assert.ok(Math.abs(insights.AAA.ranges[0].position - 0.6) < 1e-9); // (50 − 48.5) / 2.5

  assert.equal(insights.BBB.holding.value, 150); // given, not worked out
  assert.equal(insights.BBB.holding.totalChange, null); // no cost

  // $350; +$1 on the $349 before today; +$40 on the $160 the gain is known for.
  assert.equal(portfolio.count, 2);
  assert.equal(portfolio.value, 350);
  assert.equal(portfolio.dayChange, 1);
  assert.ok(Math.abs(portfolio.dayChangePct - (1 / 349) * 100) < 1e-9);
  assert.equal(portfolio.totalChange, 40);
  assert.equal(portfolio.totalChangePct, 25);
});

test("a holding counts while in its agent's newest push", () => {
  const held = { position: { shares: 2 }, signals: ["Stale"] };
  const close = "2026-10-16T11:00:00.000000+00:00"; // as_of three hours back, same push
  const { insights, portfolio } = buildHoldings(
    [quote("BTC-USD", 100, 1), quote("AAA", 50, 1, close), quote("OLD", 9, 0, close)],
    [latest("BTC-USD", held), latest("AAA", held, close, NOW), latest("OLD", held, close, EARLIER)],
  );
  assert.ok(insights["BTC-USD"].holding);
  assert.ok(insights.AAA.holding);
  assert.equal(insights.OLD, undefined); // its price stays (the quote row); nothing else to show
  assert.equal(portfolio.count, 2);
});

test("without created_at (the demo), the newest as_of is the push", () => {
  const held = { position: { shares: 1 } };
  const { insights } = buildHoldings(
    [quote("AAA", 10, 0), quote("OLD", 10, 0, EARLIER)],
    [latest("AAA", held, NOW, null), latest("OLD", held, EARLIER, null)],
  );
  assert.ok(insights.AAA.holding);
  assert.equal(insights.OLD, undefined);
});

test("hidden symbols, rows from another moment and odd data are left out", () => {
  const held = { position: { shares: 1 } };
  const { insights, portfolio } = buildHoldings(
    [quote("HID", 10, 0, NOW, { hidden: true }), quote("NEW", 10, 0), quote("ODD", 10, 0)],
    [latest("HID", held), latest("NEW", held, "2026-10-16T14:01:00Z"), latest("ODD", "not an object")],
  );
  assert.deepEqual(Object.keys(insights), []);
  assert.equal(portfolio.count, 0);
  assert.equal(portfolio.dayChange, null);
});

test("numbers and labels", () => {
  assert.equal(dataNumber("$1,234.50"), 1234.5);
  assert.equal(dataNumber("12%"), 12);
  assert.equal(dataNumber(true), null);
  assert.equal(dataNumber(""), null);
  assert.equal(compact(312000000), "312M");
  assert.equal(compact(4.66e12), "4.7T");
  assert.equal(signedPrice(-48, "USD"), "−$48.00");
  assert.equal(signedPct(30.42), "+30.4%");
  assert.equal(sharesLabel(1), "1 share");
  assert.equal(sharesLabel(0.186358), "0.1864 shares");
  assert.equal(sharesLabel(40), "40 shares");
  assert.deepEqual(signalsOf({ signals: [{ text: "x", tone: "sideways" }] }), [{ text: "x", tone: "watch" }]);
});
