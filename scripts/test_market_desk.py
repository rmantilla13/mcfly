"""market_desk.py: python3 -m unittest discover -s scripts -p 'test_*.py'"""

import datetime as dt
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import market_desk  # noqa: E402

TODAY = dt.date(2026, 10, 15)


def quote(symbol, last, prev, extended=None, extended_later=False):
    q = {"symbol": symbol, "last_trade_price": str(last), "venue_last_trade_time": "2026-10-15T19:59:59.903229751Z",
         "adjusted_previous_close": str(prev)}
    if extended is not None:
        q["last_non_reg_trade_price"] = str(extended)
        q["venue_last_non_reg_trade_time"] = "2026-10-16T04:53:55.016081411Z" if extended_later else "2026-10-15T12:00:00Z"
    return q


class MarketDeskTest(unittest.TestCase):
    def test_accounts_combine_and_the_numbers_follow(self):
        facts = {
            "positions": [
                {"symbol": "SPCX", "quantity": "26", "average_buy_price": "160.00"},
                {"symbol": "SPCX", "quantity": "1", "average_buy_price": "106.00"},  # another account
                {"symbol": "RXRX", "quantity": "3", "average_buy_price": None},
                {"symbol": "ZERO", "quantity": "0", "average_buy_price": "1"},
            ],
            "quotes": [quote("SPCX", 150, 148), quote("RXRX", 4, 4), quote("SPY", 770, 771)],
            "follow": ["SPY"],
        }
        body = market_desk.build(facts, TODAY)
        rows = {q["symbol"]: q for q in body["quotes"]}
        self.assertEqual(list(rows), ["RXRX", "SPCX", "SPY"])  # held first, then followed
        spcx = rows["SPCX"]["data"]["position"]
        self.assertEqual(spcx["shares"], 27)
        self.assertAlmostEqual(spcx["avg_cost"], 158.0)  # (26 x 160 + 106) / 27
        self.assertEqual(spcx["value"], 4050.0)
        self.assertEqual(spcx["day_change"], 54.0)  # 27 x $2
        self.assertEqual(spcx["total_change"], -216.0)  # 27 x (150 - 158)
        self.assertNotIn("total_change", rows["RXRX"]["data"]["position"])  # no cost known
        self.assertEqual(rows["SPY"]["data"], {"stats": {"prev_close": 771.0}})  # followed: no position
        self.assertEqual(rows["SPY"]["change"], -1)
        self.assertNotIn("ZERO", rows)

    def test_the_newer_trade_is_the_price(self):
        self.assertEqual(market_desk.price_of(quote("X", 100, 99, extended=103, extended_later=True)), 103)
        self.assertEqual(market_desk.price_of(quote("X", 100, 99, extended=103)), 100)
        self.assertEqual(market_desk.price_of(quote("X", 100, 99)), 100)

    def test_signals_are_facts_with_a_direction(self):
        facts = {
            "positions": [{"symbol": "TSLA", "quantity": "1", "average_buy_price": "300"}],
            "quotes": [quote("TSLA", 372, 360)],
            "fundamentals": [{"symbol": "TSLA", "volume": "60000000", "average_volume_30_days": "30000000",
                              "high_52_weeks": "498.83", "low_52_weeks": "297.38", "pe_ratio": "341.13",
                              "market_cap": "1431395911000", "dividend_yield": None}],
            "rsi": {"TSLA": 72.4},
            "sma50": {"TSLA": [365.0, 366.0]},
            "earnings": [{"symbol": "TSLA", "report": {"date": "2026-10-21", "timing": "pm"}},
                         {"symbol": "TSLA", "report": {"date": "2026-07-22", "timing": "pm"}}],  # past
            "follow": [],
        }
        data = market_desk.build(facts, TODAY)["quotes"][0]["data"]
        texts = [s["text"] for s in data["signals"]]
        self.assertEqual(texts, ["Earnings Wed Oct 21, after the close", "Crossed above its 50-day average ($366.00)",
                                 "RSI 72: above 70", "Up 3.3% since the last close"])  # at most four, volume left out
        self.assertEqual([s["tone"] for s in data["signals"]], ["watch", "up", "up", "up"])
        self.assertEqual(data["stats"]["earnings"], "Wed Oct 21, after the close")
        self.assertEqual(data["stats"]["pe"], 341.13)
        self.assertNotIn("dividend_yield", data["stats"])
        for s in data["signals"]:
            self.assertNotRegex(s["text"].lower(), r"\b(buy|sell|hold)\b")

    def test_a_52_week_low_and_a_cross_down(self):
        facts = {
            "quotes": [quote("ARKK", 50, 53)],
            "fundamentals": [{"symbol": "ARKK", "high_52_weeks": "90", "low_52_weeks": "50.5"}],
            "sma200": {"ARKK": [52.0, 51.0]},
            "follow": ["ARKK"],
        }
        texts = [s["text"] for s in market_desk.build(facts, TODAY)["quotes"][0]["data"]["signals"]]
        self.assertEqual(texts, ["Fell below its 200-day average ($51.00)", "At a 52-week low", "Down 5.7% since the last close"])

    def test_intraday_bars_on_the_session(self):
        # Oct 16, 2026: New York is on EDT, so the session is 13:30 to 20:00 UTC.
        now = dt.datetime(2026, 10, 16, 15, 47, tzinfo=dt.timezone.utc)
        facts = {
            "quotes": [quote("SPY", 768.74, 771.79)],
            "intraday": {"spy": [
                ["2026-10-16T13:40:00Z", "772.2"],
                {"begins_at": "2026-10-16T13:30:00Z", "close_price": "772.31"},
                {"begins_at": "2026-10-16T13:35:00Z", "close_price": "771.0", "interpolated": True},  # gap-fill: out
                ["2026-10-15T19:50:00Z", "771.79"],  # yesterday's session: out
                ["2026-10-16T15:40:00Z", "768.74"],
            ]},
            "intraday_interval": "5minute",
            "follow": ["SPY"],
        }
        day = market_desk.build(facts, TODAY, now)["quotes"][0]["data"]["intraday"]
        self.assertEqual(day["interval"], "5minute")
        self.assertEqual(day["open"], int(dt.datetime(2026, 10, 16, 13, 30, tzinfo=dt.timezone.utc).timestamp()))
        self.assertEqual(day["close"], int(dt.datetime(2026, 10, 16, 20, 0, tzinfo=dt.timezone.utc).timestamp()))
        self.assertEqual([p[1] for p in day["points"]], [772.31, 772.2, 768.74, 768.74])  # oldest first, then the live price
        self.assertEqual(day["points"][-1][0], int(now.timestamp()))
        # After the close, no live point; under two bars, no chart.
        after = dt.datetime(2026, 10, 16, 21, 0, tzinfo=dt.timezone.utc)
        self.assertEqual(len(market_desk.build(facts, TODAY, after)["quotes"][0]["data"]["intraday"]["points"]), 3)
        facts["intraday"] = {"SPY": [["2026-10-16T13:30:00Z", "772.31"]]}
        self.assertNotIn("intraday", market_desk.build(facts, TODAY, now)["quotes"][0].get("data", {}))

    def test_no_account_number_leaves(self):
        facts = {"positions": [{"symbol": "SPY", "quantity": "1", "average_buy_price": "700", "account_number": "5QY52076"}],
                 "quotes": [quote("SPY", 771, 770)]}
        self.assertNotIn("5QY52076", str(market_desk.build(facts, TODAY)))


if __name__ == "__main__":
    unittest.main()
