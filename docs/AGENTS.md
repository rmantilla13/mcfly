# Agents: how to push to McFly

An agent is anything that can make an HTTPS request on a schedule: a Grok or
Claude task, a cron job, a GitHub Action, the Daily Pulse pipeline, a Python
script. It needs two things from you: the ingest URL and its key.

```
URL   https://<project>.supabase.co/functions/v1/ingest/<feed>
key   Authorization: Bearer mcf_…        (or the header X-Agent-Key: mcf_…)
```

Make the agent in the console (Agents → New agent) or in the phone app; the
key is shown once. Every push is logged there (Overview → Recent pushes),
with the first problem in a sentence when something is refused.

The feeds are `briefs`, `quotes`, `news`, `projects`, `metrics`, `dashboards`,
`events` and `todos`. `POST /ingest` with a `"type"` field works too, and
`GET /ingest` answers who the key belongs to and its last ten pushes. Every
answer is JSON: `{ "ok": true, "feed": "...", "count": n, ... }` or
`{ "error": "what was wrong" }` with 400 (bad payload), 401 (no or unknown
key), 404 (unknown feed), 413 (over 1 MB) or 503 (database unreachable).
Timestamps are ISO-8601 (`2026-10-14T13:06:00Z`); a missing one means now.

`scripts/mcfly_push.py` does all of this from a shell with `MCFLY_URL` and
`MCFLY_KEY` set; `--dry-run` prints the request instead.

## Briefs (Grok's updates, alerts, anything written)

```bash
curl -X POST "$MCFLY_URL/functions/v1/ingest/briefs" \
  -H "Authorization: Bearer $MCFLY_KEY" -H "Content-Type: application/json" \
  -d '{
    "briefs": [{
      "id": "2026-10-14-09",
      "title": "Morning briefing",
      "body": "Three things for today.\n\n- The Fed minutes land at 1 PM CT.\n- Apple reports after the close.\n- Rain clears by noon.",
      "kind": "daily",
      "published_at": "2026-10-14T13:00:00Z"
    }]
  }'
```

| Field | |
|---|---|
| `title` | required, ≤200 characters |
| `body` | plain text, ≤20,000; blank lines are paragraphs, `- ` starts a bullet |
| `kind` | `hourly`, `daily`, `alert` or `update` (default) |
| `id` | your own id, ≤120; a push with the same id **replaces** the brief, so an hourly update can overwrite itself |
| `published_at`, `expires_at` | optional; an expired brief leaves the display |

One brief can be sent bare (`{ "title": ..., "body": ... }`) or as `{ "brief": {...} }`. At most 200 per push. Briefs are kept 30 days (Settings).

## Quotes (stocks)

```bash
curl -X POST "$MCFLY_URL/functions/v1/ingest/quotes" \
  -H "Authorization: Bearer $MCFLY_KEY" -H "Content-Type: application/json" \
  -d '{
    "as_of": "2026-10-14T20:00:00Z",
    "quotes": [
      { "symbol": "AAPL", "name": "Apple", "price": 247.90, "change": 2.78, "change_pct": 1.13, "note": "Services beat." },
      { "symbol": "SPY", "name": "S&P 500 ETF", "price": 668.42, "change": 2.11, "change_pct": 0.32 },
      { "symbol": "BTC-USD", "name": "Bitcoin", "price": 118420, "change_pct": -1.04 }
    ]
  }'
```

| Field | |
|---|---|
| `symbol` | required; letters, digits, `. ^ = : -`, upper-cased |
| `price` | required; a number, or a string like `"1,234.50"` |
| `change`, `change_pct` | optional; without them the display compares with the previous push |
| `name`, `note` (≤2000), `currency` (3 letters, default USD), `as_of`, `data` (any object) | optional |

Every push adds a row; the newest per symbol is what the display shows, and
the history draws its sparkline (90 days kept). New symbols appear at the end
of the list; order and hide them in the console (Feed → Markets).

### Holdings, signals and the day's numbers (`data`)

Three keys in a quote's `data` are drawn on the display: the holding on the
symbol's tile and the total over the Markets grid and on Home's ticker, the
signals as a dot on the tile and a list in its detail, the numbers in the
detail (the day and 52-week ranges as bars, with where the price sits).

```json
{ "symbol": "NVDA", "price": 191.25, "change": 2.85, "change_pct": 1.51,
  "data": {
    "position": { "shares": 60, "avg_cost": 121.80, "value": 11475, "day_change": 171.0, "total_change": 4167 },
    "signals": [
      { "text": "RSI 72: above 70 for the first time since July", "tone": "up" },
      { "text": "Earnings Nov 19, after the close", "tone": "watch" }
    ],
    "stats": { "open": 188.9, "high": 192.4, "low": 188.1, "prev_close": 188.4,
               "volume": 312000000, "avg_volume": 173000000, "market_cap": 4.66e12, "pe": 54.8,
               "low_52w": 86.6, "high_52w": 195.0, "dividend_yield": 0.02, "earnings": "Nov 19, after close" } } }
```

| Key | |
|---|---|
| `position` | `shares`, `avg_cost`, `value`, `day_change`, `total_change`, `total_change_pct`, `weight_pct`; numbers or numeric strings. The display works out what's missing: value from shares × price, the gain from the average cost, today's move from shares × change, the weight from the total |
| `signals` | up to six, each `{ "text", "tone" }` with tone `up`, `down` or `watch` (a plain string is `watch`). Facts with a direction ("crossed its 50-day average", "volume 2× average", "earnings Thursday"), not advice |
| `stats` | `open`, `high`, `low`, `prev_close`, `volume`, `avg_volume`, `market_cap`, `pe`, `low_52w`, `high_52w`, `dividend_yield` (%), `earnings` (text, ≤40); any subset |

A holding and its signals count only while they are part of the agent's
newest push: send every symbol you hold in each push, and one you sold
simply without a `position` (or not at all). Its price stays; the holding
goes. Never send account numbers: the display needs none.

## News (the Daily Pulse report)

The body is the pipeline's `items-YYYY-MM-DD.json`, unchanged:

```bash
curl -X POST "$MCFLY_URL/functions/v1/ingest/news" \
  -H "Authorization: Bearer $MCFLY_KEY" -H "Content-Type: application/json" \
  -d @items-2026-10-14.json
```

```json
{
  "date": "Oct 14, 2026",
  "slug": "2026-10-14",
  "hero": "gemini",
  "sections": [
    { "key": "s", "name": "Social", "items": [
      { "id": "reels", "h": "Instagram puts Reels first on the home tab",
        "t": "Short video is now the default feed; static posts need to earn their reach.",
        "url": "https://about.instagram.com/blog" }
    ]},
    { "key": "a", "name": "Paid Ads", "items": [ ... ] },
    { "key": "i", "name": "AI Tech", "items": [
      { "id": "gemini", "h": "Google launches Gemini 4 Argon",
        "t": "A stronger model in Search changes how brands surface in AI answers.",
        "url": "https://blog.google/innovation-and-ai/models-and-research/gemini-models/",
        "image": "https://…/og.jpg" }
    ]}
  ]
}
```

| Field | |
|---|---|
| `slug` | required; lower-case letters, digits and dashes, normally the date. A push with the same slug **replaces** the whole report |
| `date` | the display date as you write it (optional) |
| `hero` | the `id` of the top story (optional; the first story otherwise) |
| `sections[].key`, `name` | a short key (`s`, `a`, `i`) and the name shown |
| `items[].h` / `headline` | required, ≤300 |
| `items[].t` / `takeaway` | the "why it matters" line, ≤2000 |
| `items[].url` | required, http(s) |
| `items[].image` | optional. Without it McFly looks the picture up the way the pipeline does: a YouTube thumbnail for a YouTube link, else the page's `og:image`. Send `"resolve_images": false` to skip that |

At most 500 stories. The last 14 reports are kept. Several agents can push
reports (different sources); the display shows each source's newest and lets
you switch between them.

## Projects (code, launches, anything in flight)

```bash
curl -X POST "$MCFLY_URL/functions/v1/ingest/projects" \
  -H "Authorization: Bearer $MCFLY_KEY" -H "Content-Type: application/json" \
  -d '{
    "projects": [{
      "key": "mcfly", "name": "McFly", "kind": "code", "status": "active", "progress": 62,
      "summary": "The agent display.", "next_step": "Ship the dashboards screen",
      "link": "https://github.com/rmantilla13/mcfly",
      "updates": [
        { "kind": "ci", "text": "CI green on main (14 checks)", "at": "2026-10-14T19:40:00Z" },
        { "kind": "pr", "text": "#12 Dashboards screen opened", "url": "https://github.com/rmantilla13/mcfly/pull/12" }
      ]
    }]
  }'
```

| Field | |
|---|---|
| `key` | required; your id for the project (a repo name, a ticket). A push with the same key **updates** the project |
| `name` (≤120), `kind` (`code`, `task`, `launch`, `other`), `status` (`active`, `blocked`, `paused`, `done`), `progress` (0–100) | |
| `summary` (≤2000), `next_step` (≤500), `link`, `color` (`#rrggbb`), `sort_order`, `data` | optional |
| `updates[]` | `text` (required, ≤2000), `kind` (`note`, `commit`, `pr`, `ci`, `deploy`, `alert`, `done`), `url`, `at`. At most 20 per push; the same line again is not added twice; a project keeps its last 200 |

Blocked projects come first on the display and on Home. At most 100 per push.

## Metrics (any number you want to watch)

```bash
curl -X POST "$MCFLY_URL/functions/v1/ingest/metrics" \
  -H "Authorization: Bearer $MCFLY_KEY" -H "Content-Type: application/json" \
  -d '{
    "metrics": [
      { "key": "sales.today", "label": "Sales today", "value": 4280, "unit": "USD", "delta_pct": 12.5, "group": "Store" },
      { "key": "api.p95", "label": "API p95", "value": 212, "unit": "ms", "delta": -18, "group": "Ops", "note": "After the cache change." },
      { "key": "steps", "label": "Steps", "value": 6420, "group": "Me" }
    ]
  }'
```

| Field | |
|---|---|
| `key` | required; lower-case letters, digits, `. _ -` |
| `value` | required; a number or a numeric string |
| `label` (≤80), `unit` (≤16; `USD` and `%` are formatted), `delta`, `delta_pct`, `note`, `group` (≤80), `as_of`, `data` | optional |

Like quotes: every push is a point, the newest shows, the history is the
sparkline (90 days). The display groups them by `group` (Markets → Metrics);
the console orders, relabels and hides them.

## Dashboards (a board the agent lays out)

```bash
curl -X POST "$MCFLY_URL/functions/v1/ingest/dashboards" \
  -H "Authorization: Bearer $MCFLY_KEY" -H "Content-Type: application/json" \
  -d '{
    "dashboards": [{
      "key": "ops", "title": "Ops", "subtitle": "Production, last 24 h",
      "widgets": [
        { "type": "status",   "label": "API", "state": "ok", "detail": "All checks passing" },
        { "type": "metric",   "label": "Requests", "value": 1240000, "delta_pct": 4.2 },
        { "type": "progress", "label": "Storage", "value": 68, "max": 100, "unit": "%" },
        { "type": "chart",    "label": "Requests per hour", "points": [40, 42, 38, 51, 60, 64, 70], "unit": "k" },
        { "type": "list",     "title": "On call", "items": ["Ricky (primary)", "Pager quiet since Monday"] },
        { "type": "text",     "title": "Note", "body": "Deploy window tonight, 9 to 10 PM CT." }
      ]
    }]
  }'
```

| Widget | Fields |
|---|---|
| `metric` | `label`, `value`, `unit?`, `delta?`, `delta_pct?` |
| `status` | `label`, `state` (`ok`, `warn`, `down`, `unknown`), `detail?` |
| `progress` | `label`, `value`, `max` (default 100), `unit?` |
| `chart` | `label`, `points` (numbers, ≤120), `unit?` |
| `list` | `title?`, `items` (strings, ≤20) |
| `text` | `title?`, `body` (≤2000) |

`key` is required (a slug); a push with the same key **replaces** the board.
1 to 40 widgets; charts, lists and notes are drawn two columns wide. The
display shows the boards as pills (Boards); the console orders and hides them.

## Events (the calendar)

```bash
curl -X POST "$MCFLY_URL/functions/v1/ingest/events" \
  -H "Authorization: Bearer $MCFLY_KEY" -H "Content-Type: application/json" \
  -d '{
    "calendar": "Work", "replace": true,
    "events": [
      { "id": "evt-123", "title": "Standup", "starts_at": "2026-10-15T14:30:00Z", "ends_at": "2026-10-15T14:45:00Z", "color": "#5B7CF5" },
      { "id": "evt-124", "title": "Launch day", "starts_at": "2026-10-20T00:00:00-05:00", "all_day": true, "location": "Austin" }
    ]
  }'
```

| Field | |
|---|---|
| `title` (≤300), `starts_at` | required |
| `ends_at` | default: an hour later (the day, for all-day events) |
| `id` | your calendar's event id (≤200); the same id **updates** the event. Without one, the title and start identify it |
| `calendar` | the calendar's name (≤80), per event or for the whole push; default "Calendar" |
| `all_day`, `description` (≤4000), `location` (≤300), `color`, `url`, `data` | optional |
| `replace` | with a `calendar` in the body: the push is that calendar whole, and events not in it are removed. The way to mirror Google, iCloud or a calendar link: push the next weeks every hour with `replace` |

Events are kept 60 days after they end. At most 1000 per push.

## Todos and reminders

```bash
curl -X POST "$MCFLY_URL/functions/v1/ingest/todos" \
  -H "Authorization: Bearer $MCFLY_KEY" -H "Content-Type: application/json" \
  -d '{
    "todos": [
      { "id": "passport", "title": "Renew the passport", "due_at": "2026-11-02T00:00:00-06:00", "all_day": true },
      { "id": "call-mom", "kind": "reminder", "title": "Call mom", "due_at": "2026-10-16T17:30:00-05:00" },
      { "id": "invoice", "title": "Send the Q4 invoice", "done": true }
    ]
  }'
```

| Field | |
|---|---|
| `title` (≤300) | required |
| `kind` | `todo` (the default: something to do) or `reminder` (the display announces it, card and voice, at `due_at`) |
| `due_at` | a todo's deadline (optional), a reminder's time (required). With `all_day`, the day: send its local midnight |
| `id` | your id (≤200); the same id **updates** it |
| `done` | `true` checks it off (the first time is kept), `false` opens it again; left out, it stays as it was |
| `notes` (≤2000), `all_day`, `data` | optional |

The answer's `ids` are the stored rows' ids, in order. At most 200 per push.
Home's timeline shows today's: reminders at their time, todos due today,
overdue or undated at the top of the day. The assistant reads the open ones
and can check any of them off when asked. McFly's own (added by asking it)
belong to the built-in agent "McFly", which has no key.

## Reading back

`GET /ingest` with the key:

```json
{ "ok": true, "agent": { "id": "…", "name": "Grok", "slug": "grok", "kind": "grok" },
  "recent": [ { "feed": "briefs", "count": 1, "status": "ok", "message": null, "created_at": "…" } ],
  "feeds": ["briefs", "quotes", "news", "projects", "metrics", "dashboards", "events"] }
```

## Keys

A key is `mcf_` and 40 hex characters. Rotate it in the console when it
leaks (the old one stops at once); revoke the agent to stop it without
deleting what it pushed. Keys never go in a URL, a log line or a chat
message: put them in the agent's secret store.
