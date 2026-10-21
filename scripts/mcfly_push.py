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
    mcfly_push.py raw briefs payload.json           # any feed, any JSON body
    mcfly_push.py whoami

Every command prints the server's answer. --dry-run prints the request
instead of sending it. See docs/AGENTS.md for the payloads.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

FEEDS = ("briefs", "quotes", "news", "projects", "metrics", "dashboards", "events")


def settings() -> tuple[str, str]:
    url = os.environ.get("MCFLY_URL", "").rstrip("/")
    key = os.environ.get("MCFLY_KEY", "")
    if not url or not key:
        sys.exit("set MCFLY_URL (https://<project>.supabase.co) and MCFLY_KEY (the agent's key)")
    return url, key


def send(feed: str, body: dict | list | None, dry_run: bool, method: str = "POST") -> int:
    url, key = settings()
    endpoint = f"{url}/functions/v1/ingest" + (f"/{feed}" if feed else "")
    data = None if body is None else json.dumps(body).encode()
    if dry_run:
        print(f"{method} {endpoint}")
        if body is not None:
            print(json.dumps(body, indent=2))
        return 0
    request = urllib.request.Request(endpoint, data=data, method=method,
                                     headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            print(response.read().decode())
            return 0
    except urllib.error.HTTPError as error:
        print(error.read().decode() or f"HTTP {error.code}", file=sys.stderr)
        return 1
    except urllib.error.URLError as error:
        print(f"could not reach McFly: {error.reason}", file=sys.stderr)
        return 1


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
    p.add_argument("--status", choices=["active", "blocked", "paused", "done"])
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
    if args.command == "raw":
        return send(args.feed, read_json(args.file), args.dry_run)
    if args.command == "whoami":
        return send("", None, args.dry_run, method="GET")
    return 2


if __name__ == "__main__":
    sys.exit(main())
