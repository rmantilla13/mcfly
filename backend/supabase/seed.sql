-- Local development seed: three agents and a little of each feed, so the
-- display and the console have something to show. Their keys are the hashes
-- of fixed strings, printed below, so a local agent can push with them.
-- To make yourself a platform admin, see docs/ADMIN.md.
--
-- The seed runs as the database owner, not as an admin; the ingest functions
-- check for one, so the session claims to be the service role while it runs.
--
--   Grok:   mcf_0000000000000000000000000000000000grok0
--   Stocks: mcf_000000000000000000000000000000000stocks
--   Pulse:  mcf_00000000000000000000000000000000pulse00

select set_config('request.jwt.claim.role', 'service_role', false);

insert into public.agents (id, name, slug, kind, color) values
  ('00000000-0000-0000-0000-00000000a001', 'Grok', 'grok', 'grok', '#7A64E8'),
  ('00000000-0000-0000-0000-00000000a002', 'Market desk', 'market-desk', 'stocks', '#3DB37A'),
  ('00000000-0000-0000-0000-00000000a003', 'Daily Pulse', 'daily-pulse', 'news', '#E2725B');

insert into public.agent_keys (agent_id, key_hash, key_prefix) values
  ('00000000-0000-0000-0000-00000000a001', public.key_hash('mcf_0000000000000000000000000000000000grok0'), 'mcf_00000000'),
  ('00000000-0000-0000-0000-00000000a002', public.key_hash('mcf_000000000000000000000000000000000stocks'), 'mcf_00000000'),
  ('00000000-0000-0000-0000-00000000a003', public.key_hash('mcf_00000000000000000000000000000000pulse00'), 'mcf_00000000');

insert into public.briefs (agent_id, external_id, title, body, kind, published_at) values
  ('00000000-0000-0000-0000-00000000a001', 'seed-daily', 'Morning briefing',
   E'Three things for today.\n\n- The Fed minutes land at 1 PM CT; markets are pricing a hold.\n- Your 3 PM call moved to 3:30.\n- Rain clears by noon, 71° this afternoon.',
   'daily', now() - interval '3 hours'),
  ('00000000-0000-0000-0000-00000000a001', 'seed-hourly', 'Hourly check-in',
   E'Quiet hour. NVDA is leading the Nasdaq, and the Pulse report for today has landed with 11 stories.',
   'hourly', now() - interval '20 minutes');

insert into public.quotes (agent_id, symbol, name, price, change, change_pct, note, as_of) values
  ('00000000-0000-0000-0000-00000000a002', 'AAPL', 'Apple',       245.12,  1.42,  0.58, null, now() - interval '1 day'),
  ('00000000-0000-0000-0000-00000000a002', 'AAPL', 'Apple',       247.90,  2.78,  1.13, 'Services beat; iPhone 18 demand steady.', now()),
  ('00000000-0000-0000-0000-00000000a002', 'NVDA', 'NVIDIA',      188.40, -3.10, -1.62, null, now() - interval '1 day'),
  ('00000000-0000-0000-0000-00000000a002', 'NVDA', 'NVIDIA',      191.25,  2.85,  1.51, null, now()),
  ('00000000-0000-0000-0000-00000000a002', 'TSLA', 'Tesla',       402.10,  5.30,  1.34, null, now()),
  ('00000000-0000-0000-0000-00000000a002', 'SPY',  'S&P 500 ETF', 668.42,  2.11,  0.32, null, now());
insert into public.symbols (symbol, name, sort_order) values
  ('SPY', 'S&P 500 ETF', 0), ('AAPL', 'Apple', 1), ('NVDA', 'NVIDIA', 2), ('TSLA', 'Tesla', 3);

select public.ingest_news('00000000-0000-0000-0000-00000000a003', $json$
{
  "date": "Oct 14, 2026",
  "slug": "2026-10-14",
  "hero": "gemini",
  "sections": [
    {"key": "s", "name": "Social", "items": [
      {"id": "reels", "h": "Instagram puts Reels first on the home tab", "t": "Short video is now the default feed; static posts need to earn their reach.", "url": "https://about.instagram.com/blog"},
      {"id": "tiktok", "h": "TikTok Shop adds live auctions in the US", "t": "Live commerce keeps growing; brands with hosts win.", "url": "https://newsroom.tiktok.com/"}
    ]},
    {"key": "a", "name": "Paid Ads", "items": [
      {"id": "pmax", "h": "Google adds channel-level reporting to Performance Max", "t": "You can finally see where the spend goes.", "url": "https://blog.google/products/ads-commerce/"},
      {"id": "meta", "h": "Meta Advantage+ gets a creative-only mode", "t": "Hand it the assets and it builds the campaign.", "url": "https://www.facebook.com/business/news"}
    ]},
    {"key": "i", "name": "AI Tech", "items": [
      {"id": "gemini", "h": "Google launches Gemini 4 Argon", "t": "A stronger model in Search changes how brands surface in AI answers.", "url": "https://blog.google/innovation-and-ai/models-and-research/gemini-models/"},
      {"id": "claude", "h": "Anthropic ships Claude 5 to everyone", "t": "Computer use is on by default; expect agents in every workflow tool.", "url": "https://www.anthropic.com/news"}
    ]}
  ]
}
$json$::jsonb);
select public.record_ingest('00000000-0000-0000-0000-00000000a001', 'briefs', 2, 'ok');
select public.record_ingest('00000000-0000-0000-0000-00000000a002', 'quotes', 4, 'ok');
select public.record_ingest('00000000-0000-0000-0000-00000000a003', 'news', 6, 'ok');

-- A code agent, a metrics agent and a calendar agent, with a little of each feed.
insert into public.agents (id, name, slug, kind, color) values
  ('00000000-0000-0000-0000-00000000a004', 'GitHub watcher', 'github-watcher', 'other', '#5B7CF5'),
  ('00000000-0000-0000-0000-00000000a005', 'Ops metrics', 'ops-metrics', 'other', '#F6B94A'),
  ('00000000-0000-0000-0000-00000000a006', 'Calendar sync', 'calendar-sync', 'other', '#14C2C2');
insert into public.agent_keys (agent_id, key_hash, key_prefix) values
  ('00000000-0000-0000-0000-00000000a004', public.key_hash('mcf_00000000000000000000000000000000github0'), 'mcf_00000000'),
  ('00000000-0000-0000-0000-00000000a005', public.key_hash('mcf_0000000000000000000000000000000000ops00'), 'mcf_00000000'),
  ('00000000-0000-0000-0000-00000000a006', public.key_hash('mcf_000000000000000000000000000000calendar0'), 'mcf_00000000');

select public.ingest_projects('00000000-0000-0000-0000-00000000a004', $json$[
  {"key": "mcfly", "name": "McFly", "kind": "code", "status": "active", "progress": 62, "sort_order": 0,
   "stages": ["Plan", "Build", "Review", "Ship"], "stage": "Build",
   "summary": "The agent display: Pi app, console and the iPhone app.", "next_step": "Ship the dashboards screen",
   "link": "https://github.com/rmantilla13/mcfly",
   "updates": [{"kind": "ci", "text": "CI green on main (14 checks)", "at": "2026-10-14T19:40:00Z"},
               {"kind": "pr", "text": "#12 Dashboards screen: opened by Ricky", "url": "https://github.com/rmantilla13/mcfly/pull/12", "at": "2026-10-14T18:05:00Z"}]},
  {"key": "onyx", "name": "Onyx", "kind": "code", "status": "blocked", "progress": 80, "sort_order": 1,
   "stages": ["Plan", "Build", "App Review", "Release"], "stage": "App Review",
   "summary": "Collections and the Mac app.", "next_step": "App Review answer on the FSKit entitlement",
   "updates": [{"kind": "alert", "text": "App Review: waiting on the FSKit entitlement", "at": "2026-10-13T22:00:00Z"}]},
  {"key": "homestead", "name": "Homestead", "kind": "launch", "status": "paused", "progress": 95, "sort_order": 2,
   "stages": ["Write", "Record", "Beta", "Launch"], "stage": "Launch",
   "summary": "Voice handbook app; launch copy is done."}
]$json$::jsonb);

select public.ingest_metrics('00000000-0000-0000-0000-00000000a005', $json$[
  {"key": "sales.today", "label": "Sales today", "value": 4280, "unit": "USD", "delta_pct": 12.5, "group": "Store"},
  {"key": "orders.open", "label": "Open orders", "value": 17, "delta": -3, "group": "Store"},
  {"key": "site.uptime", "label": "Uptime", "value": 99.98, "unit": "%", "group": "Ops"},
  {"key": "api.p95", "label": "API p95", "value": 212, "unit": "ms", "delta": -18, "group": "Ops", "note": "After the cache change."},
  {"key": "steps", "label": "Steps", "value": 6420, "delta_pct": -8, "group": "Me"}
]$json$::jsonb, now());
select public.ingest_metrics('00000000-0000-0000-0000-00000000a005', $json$[
  {"key": "sales.today", "value": 3800}, {"key": "api.p95", "value": 230}, {"key": "steps", "value": 7010}
]$json$::jsonb, now() - interval '1 day');

select public.ingest_dashboards('00000000-0000-0000-0000-00000000a005', $json$[
  {"key": "ops", "title": "Ops", "subtitle": "Production, last 24 h", "sort_order": 0, "widgets": [
     {"type": "status", "label": "API", "state": "ok", "detail": "All checks passing"},
     {"type": "status", "label": "Workers", "state": "warn", "detail": "1 of 4 behind"},
     {"type": "metric", "label": "Requests", "value": 1240000, "unit": "", "delta_pct": 4.2},
     {"type": "metric", "label": "Errors", "value": 0.12, "unit": "%", "delta_pct": -30},
     {"type": "progress", "label": "Storage", "value": 68, "max": 100, "unit": "%"},
     {"type": "chart", "label": "Requests per hour", "points": [40, 42, 38, 51, 60, 58, 64, 70, 66, 72, 75, 71], "unit": "k"},
     {"type": "list", "title": "On call", "items": ["Ricky (primary)", "Pager: quiet since Mon"]},
     {"type": "text", "title": "Note", "body": "Deploy window tonight 9–10 PM CT."}]},
  {"key": "launch", "title": "Launch week", "sort_order": 1, "widgets": [
     {"type": "progress", "label": "Checklist", "value": 14, "max": 20},
     {"type": "list", "title": "Left to do", "items": ["App Store screenshots", "Press list", "Support page"]},
     {"type": "metric", "label": "Waitlist", "value": 812, "delta": 46}]}
]$json$::jsonb);

select public.ingest_events('00000000-0000-0000-0000-00000000a006', $json$[
  {"id": "ev-1", "calendar": "Work", "title": "Standup", "starts_at": "2026-10-14T14:30:00Z", "ends_at": "2026-10-14T14:45:00Z", "color": "#5B7CF5"},
  {"id": "ev-2", "calendar": "Work", "title": "Pulse review with the team", "starts_at": "2026-10-14T20:30:00Z", "ends_at": "2026-10-14T21:00:00Z", "location": "Zoom", "color": "#5B7CF5"},
  {"id": "ev-3", "calendar": "Home", "title": "Dinner with Lina", "starts_at": "2026-10-15T00:00:00Z", "ends_at": "2026-10-15T02:00:00Z", "location": "Maria's", "color": "#F07F5A"},
  {"id": "ev-4", "calendar": "Work", "title": "Investor call", "starts_at": "2026-10-15T16:00:00Z", "ends_at": "2026-10-15T17:00:00Z", "color": "#5B7CF5"},
  {"id": "ev-5", "calendar": "Home", "title": "Flight to Austin", "starts_at": "2026-10-17T13:00:00Z", "ends_at": "2026-10-17T16:00:00Z", "color": "#F07F5A"},
  {"id": "ev-6", "calendar": "Home", "title": "Launch day", "starts_at": "2026-10-20T05:00:00Z", "ends_at": "2026-10-21T04:59:59Z", "all_day": true, "color": "#F6B94A"}
]$json$::jsonb, 'Work');

select set_config('request.jwt.claim.role', '', false);
