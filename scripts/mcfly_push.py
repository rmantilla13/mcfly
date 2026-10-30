#!/usr/bin/env python3
"""Push to McFly from any agent box: one file, no dependencies beyond Python 3.

    export MCFLY_URL=https://<project>.supabase.co
    export MCFLY_KEY=mcf_...                      # the agent's key, from the console

    mcfly_push.py brief "Morning briefing" --body "Three things today..." --kind daily
    mcfly_push.py quote AAPL 247.90 --change 2.78 --pct 1.13 --name Apple --note "Services beat"
    mcfly_push.py news items-2026-10-14.json       # the Daily Pulse items JSON, as is
    mcfly_push.py project mcfly --name McFly --status active --progress 62 --next "Ship it" \\
        --stages "Plan, Build, Review, Ship" --stage Build --update "ci: CI green on main"
    mcfly_push.py metric sales.today 4280 --unit USD --pct 12.5 --group Store
    mcfly_push.py event "Standup" 2026-10-15T09:30 --end 2026-10-15T09:45 --calendar Work
    mcfly_push.py dashboard ops.json                # { key, title, widgets: [...] }
    mcfly_push.py ask ship-2.3 "Ship v2.3 to TestFlight?" --choices "Ship it, Hold" --wait 3600
    mcfly_push.py answers ship-2.3                  # your asks and their answers (--open: still waiting)
    mcfly_push.py withdraw ship-2.3                 # take a question back
    mcfly_push.py raw briefs payload.json           # any feed, any JSON body
    mcfly_push.py whoami

Every command prints the server's answer. `ask` asks again each time it
runs: an id taken back, or one that ran out, is open again, with the new
--expires or none. `ask --wait` instead waits for the person and prints only
the choice they picked (exit 0, also when it was answered before), or exits
3 if the wait ran out with the question still open, 4 if it was withdrawn or
ran out itself, and 1 on an error, a revoked key included; a dropped
connection or a slow reply while waiting is tried again. --dry-run prints
the request instead of sending it. See docs/AGENTS.md for the payloads.
"""

from __future__ import annotations

import argparse
import http.client
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

FEEDS = ("briefs", "quotes", "news", "projects", "metrics", "dashboards", "events", "todos", "asks")


def settings() -> tuple[str, str]:
    url = os.environ.get("MCFLY_URL", "").rstrip("/")
    key = os.environ.get("MCFLY_KEY", "")
    if not url or not key:
        sys.exit("set MCFLY_URL (https://<project>.supabase.co) and MCFLY_KEY (the agent's key)")
    return url, key


def call(feed: str, body: dict | list | None, method: str = "POST", query: str = "") -> tuple[bool, str, int | None]:
    """The server's answer as (ok, text, HTTP status); text is the error
    sentence when not ok, and the status is None when McFly wasn't reached."""
    url, key = settings()
    endpoint = f"{url}/functions/v1/ingest" + (f"/{feed}" if feed else "") + query
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(endpoint, data=data, method=method,
                                     headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return True, response.read().decode(errors="replace"), response.status
    except urllib.error.HTTPError as error:
        try:
            text = error.read().decode(errors="replace")
        except (OSError, http.client.HTTPException):
            text = ""
        return False, text or f"HTTP {error.code}", error.code
    except urllib.error.URLError as error:
        return False, f"could not reach McFly: {error.reason}", None
    # urllib doesn't wrap what reading the response raises: a timeout, a
    # dropped connection, a reply cut short.
    except (OSError, http.client.HTTPException) as error:
        return False, f"could not reach McFly: {str(error) or type(error).__name__}", None


def send(feed: str, body: dict | list | None, dry_run: bool, method: str = "POST", query: str = "") -> int:
    if dry_run:
        url, _ = settings()
        print(f"{method} {url}/functions/v1/ingest" + (f"/{feed}" if feed else "") + query)
        if body is not None:
            print(json.dumps(body, indent=2))
        return 0
    ok, text, _ = call(feed, body, method, query)
    print(text, file=sys.stdout if ok else sys.stderr)
    return 0 if ok else 1


def asks_in(text: str) -> list[dict] | None:
    """The asks in a reply from /ingest/asks, or None when it isn't one (not
    JSON, or no list of asks: a proxy's page, a reply cut short)."""
    try:
        reply = json.loads(text)
    except ValueError:
        return None
    asks = reply.get("asks") if isinstance(reply, dict) else None
    return [a for a in asks if isinstance(a, dict)] if isinstance(asks, list) else None


def settled(ask: dict) -> int | None:
    """Prints how an ask ended and returns the exit status, or None while it's open."""
    status = ask.get("status")
    if status == "answered":
        print(ask.get("answer"))
        return 0
    if status == "open":
        return None
    print(f"{ask.get('id')} is {status}, not answered", file=sys.stderr)
    return 4


def wait_for_answer(ask_id: str, seconds: float, every: float = 5.0) -> int:
    """Polls GET /ingest/asks until the person answers; prints the choice.

    A failed or garbled poll is tried again until the time runs out, except a
    key the server refuses (401, 403) or a route it doesn't know (404): those
    won't get better by waiting, so it stops at once with exit 1."""
    deadline = time.monotonic() + seconds
    query = "?" + urllib.parse.urlencode({"id": ask_id})
    while True:
        ok, text, status = call("asks", None, "GET", query)
        asks = asks_in(text) if ok else None
        if asks is not None:
            ask = next((a for a in asks if a.get("id") == ask_id), None)
            if ask is None:
                print(f"{ask_id} is missing, not answered", file=sys.stderr)
                return 4
            done = settled(ask)
            if done is not None:
                return done
        elif ok:
            print(f"McFly's answer didn't list the asks: {text[:200]}", file=sys.stderr)
        elif status in (401, 403, 404):
            print(text, file=sys.stderr)
            return 1
        else:
            print(text, file=sys.stderr)
        if time.monotonic() + every > deadline:
            print(f"no answer to {ask_id} yet; it stays open", file=sys.stderr)
            return 3
        time.sleep(every)


def read_json(path: str):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def drop_none(d: dict) -> dict:
    return {k: v for k, v in d.items() if v is not None}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="print the request instead of sending it")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("brief", help="a text update")
    p.add_argument("title")
    p.add_argument("--body", default="")
    p.add_argument("--kind", choices=["hourly", "daily", "alert", "update"], default="update")
    p.add_argument("--id", help="your own id; a re-push with the same id replaces the brief")
    p.add_argument("--at", help="published_at, ISO-8601")

    p = sub.add_parser("quote", help="one stock quote")
    p.add_argument("symbol")
    p.add_argument("price", type=float)
    p.add_argument("--change", type=float)
    p.add_argument("--pct", type=float, help="change in percent")
    p.add_argument("--name")
    p.add_argument("--note")
    p.add_argument("--currency", default="USD")
    p.add_argument("--as-of")

    p = sub.add_parser("news", help="a Daily Pulse items JSON file")
    p.add_argument("file")
    p.add_argument("--no-images", action="store_true", help="don't look up og:images for stories without one")

    p = sub.add_parser("project", help="a project and its status")
    p.add_argument("key")
    p.add_argument("--name")
    p.add_argument("--kind", choices=["code", "task", "launch", "other"])
    p.add_argument("--status", choices=["planned", "active", "blocked", "paused", "done"])
    p.add_argument("--progress", type=int)
    p.add_argument("--summary")
    p.add_argument("--next", dest="next_step")
    p.add_argument("--link")
    p.add_argument("--stages", help='the steps in order, comma-separated: "Plan, Build, Review, Ship"')
    p.add_argument("--stage", help="the one it is in now")
    p.add_argument("--update", action="append", default=[], help='"kind: text" or just text; repeatable')

    p = sub.add_parser("metric", help="one number")
    p.add_argument("key")
    p.add_argument("value", type=float)
    p.add_argument("--label")
    p.add_argument("--unit")
    p.add_argument("--delta", type=float)
    p.add_argument("--pct", type=float)
    p.add_argument("--note")
    p.add_argument("--group")
    p.add_argument("--as-of")

    p = sub.add_parser("event", help="a calendar event")
    p.add_argument("title")
    p.add_argument("start", help="ISO-8601 start")
    p.add_argument("--end")
    p.add_argument("--all-day", action="store_true")
    p.add_argument("--calendar", default="Calendar")
    p.add_argument("--id")
    p.add_argument("--location")
    p.add_argument("--url")
    p.add_argument("--color")

    p = sub.add_parser("dashboard", help="a dashboard JSON file ({ key, title, widgets })")
    p.add_argument("file")

    p = sub.add_parser("ask", help="a question for the person, with 2 to 4 choices (Yes and No by default)")
    p.add_argument("id", help="your own id: read the answer back by it, and a re-push with it changes the question")
    p.add_argument("question")
    p.add_argument("--choices", help='comma-separated, 2 to 4: "Ship it, Hold"')
    p.add_argument("--detail", help="a line or two of context under the question")
    p.add_argument("--url", help="a link for more (the display shows its QR code)")
    p.add_argument("--expires", help="when the question stops mattering, ISO-8601")
    p.add_argument("--wait", type=float, metavar="SECONDS", help="wait this long for the answer and print only it")

    p = sub.add_parser("answers", help="your asks and their answers")
    p.add_argument("ids", nargs="*", help="your own ids; none: the last 100")
    p.add_argument("--open", action="store_true", help="only the ones still waiting")

    p = sub.add_parser("withdraw", help="take a question back")
    p.add_argument("id")

    p = sub.add_parser("raw", help="any feed with a JSON file as the body")
    p.add_argument("feed", choices=FEEDS)
    p.add_argument("file")

    sub.add_parser("whoami", help="which agent this key is, and its last pushes")

    args = parser.parse_args(argv)
    if args.command == "brief":
        body = {"briefs": [drop_none({"id": args.id, "title": args.title, "body": args.body, "kind": args.kind, "published_at": args.at})]}
        return send("briefs", body, args.dry_run)
    if args.command == "quote":
        quote = drop_none({"symbol": args.symbol, "price": args.price, "change": args.change, "change_pct": args.pct,
                           "name": args.name, "note": args.note, "currency": args.currency, "as_of": args.as_of})
        return send("quotes", {"quotes": [quote]}, args.dry_run)
    if args.command == "news":
        report = read_json(args.file)
        if args.no_images:
            report["resolve_images"] = False
        return send("news", report, args.dry_run)
    if args.command == "project":
        updates = []
        for line in args.update:
            kind, _, text = line.partition(":")
            if text and kind.strip() in ("note", "commit", "pr", "ci", "deploy", "alert", "done"):
                updates.append({"kind": kind.strip(), "text": text.strip()})
            else:
                updates.append({"text": line.strip()})
        project = drop_none({"key": args.key, "name": args.name, "kind": args.kind, "status": args.status, "progress": args.progress,
                             "summary": args.summary, "next_step": args.next_step, "link": args.link,
                             "stages": [s.strip() for s in args.stages.split(",") if s.strip()] if args.stages is not None else None,
                             "stage": args.stage, "updates": updates or None})
        return send("projects", {"projects": [project]}, args.dry_run)
    if args.command == "metric":
        metric = drop_none({"key": args.key, "value": args.value, "label": args.label, "unit": args.unit, "delta": args.delta,
                            "delta_pct": args.pct, "note": args.note, "group": args.group, "as_of": args.as_of})
        return send("metrics", {"metrics": [metric]}, args.dry_run)
    if args.command == "event":
        event = drop_none({"id": args.id, "calendar": args.calendar, "title": args.title, "starts_at": args.start, "ends_at": args.end,
                           "all_day": True if args.all_day else None, "location": args.location, "url": args.url, "color": args.color})
        return send("events", {"events": [event]}, args.dry_run)
    if args.command == "dashboard":
        return send("dashboards", {"dashboards": [read_json(args.file)]}, args.dry_run)
    if args.command == "ask":
        choices = [c.strip() for c in args.choices.split(",") if c.strip()] if args.choices else None
        ask = drop_none({"id": args.id, "question": args.question, "choices": choices, "detail": args.detail, "url": args.url})
        # Asking is asking now: an id taken back or run out opens again, and
        # an expiry left out clears the old one (null) instead of keeping it.
        ask["withdrawn"] = False
        ask["expires_at"] = args.expires
        if args.wait is None or args.dry_run:
            return send("asks", {"asks": [ask]}, args.dry_run)
        ok, text, _ = call("asks", {"asks": [ask]})
        if not ok:
            print(text, file=sys.stderr)
            return 1
        # The reply says where the ask stands, under the id the server keeps
        # (trimmed and cut to 200 characters, or made up when none was given).
        asks = asks_in(text)
        stands = asks[0] if asks else None
        if stands is None or not isinstance(stands.get("id"), str) or not stands["id"]:
            print(f"McFly's answer didn't say where the ask stands: {text[:200]}", file=sys.stderr)
            return 1
        done = settled(stands)
        return done if done is not None else wait_for_answer(stands["id"], args.wait)
    if args.command == "answers":
        query = {"id": ",".join(args.ids)} if args.ids else {}
        if args.open:
            query["open"] = "1"
        return send("asks", None, args.dry_run, method="GET", query=("?" + urllib.parse.urlencode(query)) if query else "")
    if args.command == "withdraw":
        return send("asks", {"asks": [{"id": args.id, "withdrawn": True}]}, args.dry_run)
    if args.command == "raw":
        return send(args.feed, read_json(args.file), args.dry_run)
    if args.command == "whoami":
        return send("", None, args.dry_run, method="GET")
    return 2


if __name__ == "__main__":
    sys.exit(main())
