#!/usr/bin/env python3
"""The Market desk's push, from what a brokerage connector read: one file in,
one quotes push out (docs/AGENTS.md, "Holdings, signals and the day's numbers").

    export MCFLY_URL=https://<project>.supabase.co MCFLY_KEY=mcf_...
    market_desk.py facts.json              # push
    market_desk.py facts.json --dry-run    # print the request instead

The agent that runs this (a scheduled Claude task with read-only brokerage
tools) only copies what the tools answered into facts.json, under the tools'
own field names; the arithmetic is here, where it can be tested:

    {
      "positions":    [{ "symbol", "quantity", "average_buy_price" }, ...],   every row of every account
      "quotes":       [{ "symbol", "last_trade_price", "venue_last_trade_time",
                         "last_non_reg_trade_price", "venue_last_non_reg_trade_time",
                         "adjusted_previous_close" }, ...],
      "fundamentals": [{ "symbol", "open", "high", "low", "volume", "average_volume_30_days",
                         "market_cap", "pe_ratio", "high_52_weeks", "low_52_weeks", "dividend_yield" }, ...],
      "rsi":          { "TSLA": 49.3, ... },                   14-day RSI, latest bar
      "sma50":        { "TSLA": [357.94, 358.85], ... },       the last two daily bars
      "sma200":       { "TSLA": [..., ...], ... },
      "earnings":     [{ "symbol", "report": { "date", "timing" } }, ...],
      "intraday":     { "TSLA": [["2026-10-16T13:30:00Z", "366.525"], ...], ... },
                                                               today's bars: begins_at, close_price
      "intraday_interval": "10minute",
      "follow":       ["SPY", "QQQ", ...]                      shown without a position too
    }

A symbol held in several accounts is one holding (shares summed, cost
averaged by shares). Signals are facts with a direction, never advice.
No account number goes into the push.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mcfly_push  # noqa: E402

DEFAULT_FOLLOW = ["SPY", "QQQ", "NVDA", "AAPL", "MSFT"]
MAX_SIGNALS = 4
BIG_MOVE_PCT = 3.0
HEAVY_VOLUME = 1.5
EARNINGS_SOON_DAYS = 7
# US equities' regular session, in New York time.
NEW_YORK = "America/New_York"
SESSION_OPEN, SESSION_CLOSE = dt.time(9, 30), dt.time(16, 0)


def num(value) -> float | None:
    """A finite number from a tool's field (they come as strings), else None."""
    if value is None or isinstance(value, bool):
        return None
    try:
        n = float(str(value).replace(",", "").replace("$", ""))
    except ValueError:
        return None
    return n if n == n and abs(n) != float("inf") else None


def when(value) -> dt.datetime | None:
    if not value:
        return None
    text = str(value).replace("Z", "+00:00")
    # Python's fromisoformat takes at most six digits of a fraction; the tools send nine.
    if "." in text:
        head, _, rest = text.partition(".")
        n = len(rest) - len(rest.lstrip("0123456789"))
        text = head + "." + rest[:min(n, 6)].ljust(6, "0") + rest[n:]
    try:
        return dt.datetime.fromisoformat(text)
    except ValueError:
        return None


def by_symbol(rows) -> dict:
    return {str(r.get("symbol", "")).upper(): r for r in rows or [] if r.get("symbol")}


def price_of(quote: dict) -> float | None:
    """The newer of the regular-session and the extended-hours trade."""
    regular, extended = num(quote.get("last_trade_price")), num(quote.get("last_non_reg_trade_price"))
    if extended is None:
        return regular
    if regular is None:
        return extended
    t_regular, t_extended = when(quote.get("venue_last_trade_time")), when(quote.get("venue_last_non_reg_trade_time"))
    return extended if t_regular and t_extended and t_extended > t_regular else regular


def holdings(positions) -> dict:
    """{ symbol: (shares, avg_cost or None) }, accounts combined."""
    held: dict[str, list[float]] = {}
    for row in positions or []:
        symbol = str(row.get("symbol", "")).upper()
        shares = num(row.get("quantity"))
        if not symbol or not shares:
            continue
        avg = num(row.get("average_buy_price"))
        entry = held.setdefault(symbol, [0.0, 0.0, 0.0])  # shares, cost, shares with a known cost
        entry[0] += shares
        if avg is not None:
            entry[1] += shares * avg
            entry[2] += shares
    return {s: (e[0], e[1] / e[2] if e[2] else None) for s, e in held.items()}


def money(n: float) -> str:
    return f"${n:,.2f}"


def earnings_label(entry: dict, today: dt.date) -> tuple[str, int] | None:
    report = entry.get("report") or {}
    try:
        day = dt.date.fromisoformat(str(report.get("date")))
    except ValueError:
        return None
    days = (day - today).days
    if days < 0:
        return None
    timing = {"am": "before the open", "pm": "after the close"}.get(str(report.get("timing")), "")
    name = "today" if days == 0 else "tomorrow" if days == 1 else day.strftime("%a %b %-d") if days < 7 else day.strftime("%b %-d")
    return (f"{name}, {timing}" if timing else name), days


def signals_for(symbol, price, prev_close, change_pct, fund, rsi, sma50, sma200, earnings, today) -> list[dict]:
    found: list[dict] = []
    if earnings and earnings[1] <= EARNINGS_SOON_DAYS:
        found.append({"text": f"Earnings {earnings[0]}", "tone": "watch"})
    for days, sma in ((50, sma50), (200, sma200)):
        if not sma or len(sma) < 2 or prev_close is None:
            continue
        before, now = num(sma[-2]), num(sma[-1])
        if before is None or now is None:
            continue
        if prev_close < before and price >= now:
            found.append({"text": f"Crossed above its {days}-day average ({money(now)})", "tone": "up"})
        elif prev_close > before and price <= now:
            found.append({"text": f"Fell below its {days}-day average ({money(now)})", "tone": "down"})
    high, low = num(fund.get("high_52_weeks")), num(fund.get("low_52_weeks"))
    if high and price >= high:
        found.append({"text": "At a 52-week high", "tone": "up"})
    elif high and price >= high * 0.98:
        found.append({"text": f"Within 2% of its 52-week high ({money(high)})", "tone": "up"})
    elif low and price <= low:
        found.append({"text": "At a 52-week low", "tone": "down"})
    elif low and price <= low * 1.02:
        found.append({"text": f"Within 2% of its 52-week low ({money(low)})", "tone": "down"})
    if rsi is not None and rsi >= 70:
        found.append({"text": f"RSI {rsi:.0f}: above 70", "tone": "up"})
    elif rsi is not None and rsi <= 30:
        found.append({"text": f"RSI {rsi:.0f}: below 30", "tone": "down"})
    if change_pct is not None and abs(change_pct) >= BIG_MOVE_PCT:
        word = "Up" if change_pct > 0 else "Down"
        found.append({"text": f"{word} {abs(change_pct):.1f}% since the last close", "tone": "up" if change_pct > 0 else "down"})
    volume, avg_volume = num(fund.get("volume")), num(fund.get("average_volume_30_days") or fund.get("average_volume"))
    if volume and avg_volume and volume >= HEAVY_VOLUME * avg_volume:
        found.append({"text": f"Volume {volume / avg_volume:.1f}× its 30-day average", "tone": "watch"})
    return found[:MAX_SIGNALS]


def intraday_of(bars, interval: str, price: float, now: dt.datetime) -> dict | None:
    """The newest session's bars as [[epoch seconds, price], ...] with its
    bounds (open, close: epoch seconds, New York's 9:30 to 16:00), so a chart
    can lay the day out on the whole session; the live price is the newest
    point while the session is on. None with fewer than two bars."""
    from zoneinfo import ZoneInfo

    seen: dict[int, float] = {}
    for bar in bars or []:
        if isinstance(bar, dict):
            if bar.get("interpolated"):
                continue
            t, p = when(bar.get("begins_at")), num(bar.get("close_price"))
        elif isinstance(bar, (list, tuple)) and len(bar) >= 2:
            t, p = when(bar[0]), num(bar[1])
        else:
            continue
        if t is not None and p is not None:
            seen[int(t.timestamp())] = p
    if len(seen) < 2:
        return None
    ny = ZoneInfo(NEW_YORK)
    day = dt.datetime.fromtimestamp(max(seen), ny).date()
    open_ = int(dt.datetime.combine(day, SESSION_OPEN, ny).timestamp())
    close = int(dt.datetime.combine(day, SESSION_CLOSE, ny).timestamp())
    points = sorted((t, p) for t, p in seen.items() if open_ <= t < close)
    if len(points) < 2:
        return None
    t_now = int(now.timestamp())
    if points[-1][0] < t_now < close:
        points.append((t_now, price))
    return {"interval": interval, "open": open_, "close": close, "points": [[t, round(p, 4)] for t, p in points]}


def build(facts: dict, today: dt.date | None = None, now: dt.datetime | None = None) -> dict:
    """The quotes push for facts.json: every held and followed symbol."""
    today = today or dt.date.today()
    now = now or dt.datetime.now(dt.timezone.utc)
    bars = {str(k).upper(): v for k, v in (facts.get("intraday") or {}).items()}
    interval = str(facts.get("intraday_interval") or "10minute")
    held = holdings(facts.get("positions"))
    quotes, funds = by_symbol(facts.get("quotes")), by_symbol(facts.get("fundamentals"))
    rsi, sma50, sma200 = facts.get("rsi") or {}, facts.get("sma50") or {}, facts.get("sma200") or {}
    earnings = {}
    for entry in facts.get("earnings") or []:
        label = earnings_label(entry, today)
        symbol = str(entry.get("symbol", "")).upper()
        if label and (symbol not in earnings or label[1] < earnings[symbol][1]):
            earnings[symbol] = label
    follow = [str(s).upper() for s in facts.get("follow") or DEFAULT_FOLLOW]
    symbols = sorted(held) + [s for s in follow if s not in held]

    out = []
    for symbol in symbols:
        quote = quotes.get(symbol)
        price = price_of(quote) if quote else None
        if price is None:
            continue
        prev_close = num(quote.get("adjusted_previous_close"))
        change = price - prev_close if prev_close is not None else None
        change_pct = change / prev_close * 100 if change is not None and prev_close else None
        fund = funds.get(symbol, {})
        data: dict = {}
        if symbol in held:
            shares, avg = held[symbol]
            position = {"shares": round(shares, 6), "value": round(shares * price, 2)}
            if avg is not None:
                position["avg_cost"] = round(avg, 4)
                position["total_change"] = round(shares * (price - avg), 2)
            if change is not None:
                position["day_change"] = round(shares * change, 2)
            data["position"] = position
        found = signals_for(symbol, price, prev_close, change_pct, fund, num(rsi.get(symbol)),
                            sma50.get(symbol), sma200.get(symbol), earnings.get(symbol), today)
        if found:
            data["signals"] = found
        stats = {
            "open": num(fund.get("open")), "high": num(fund.get("high")), "low": num(fund.get("low")),
            "prev_close": prev_close, "volume": num(fund.get("volume")),
            "avg_volume": num(fund.get("average_volume_30_days") or fund.get("average_volume")),
            "market_cap": num(fund.get("market_cap")), "pe": num(fund.get("pe_ratio")),
            "low_52w": num(fund.get("low_52_weeks")), "high_52w": num(fund.get("high_52_weeks")),
            "dividend_yield": num(fund.get("dividend_yield")),
            "earnings": earnings[symbol][0] if symbol in earnings else None,
        }
        stats = {k: v for k, v in stats.items() if v is not None}
        if stats:
            data["stats"] = stats
        intraday = intraday_of(bars.get(symbol), interval, price, now)
        if intraday:
            data["intraday"] = intraday
        row = {"symbol": symbol, "price": round(price, 4)}
        if change is not None:
            row["change"] = round(change, 4)
            row["change_pct"] = round(change_pct, 4)
        if data:
            row["data"] = data
        out.append(row)
    return {"as_of": now.isoformat(timespec="seconds"), "quotes": out}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("facts", help="the facts JSON file")
    parser.add_argument("--dry-run", action="store_true", help="print the request instead of sending it")
    args = parser.parse_args(argv)
    body = build(mcfly_push.read_json(args.facts))
    if not body["quotes"]:
        print("no quotes to push: the facts had no prices", file=sys.stderr)
        return 1
    held = sum(1 for q in body["quotes"] if "position" in q.get("data", {}))
    print(f"{len(body['quotes'])} quotes, {held} holdings", file=sys.stderr)
    if args.dry_run:  # needs no key: the body is the point
        print(json.dumps(body, indent=2))
        return 0
    return mcfly_push.send("quotes", body, False)


if __name__ == "__main__":
    sys.exit(main())
