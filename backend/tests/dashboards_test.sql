-- Dashboards made in the console (20261016000010): a recipe of parts drawn
-- into the six widgets, redrawn when what they pull from changes, never in
-- the way of an agent's push, and read by displays like any board.
\set ON_ERROR_STOP 1
\set grok   '00000000-0000-0000-0000-00000000a001'
\set stocks '00000000-0000-0000-0000-00000000a002'
\set ops    '00000000-0000-0000-0000-00000000a005'
\set cal    '00000000-0000-0000-0000-00000000a006'
\set device 'd0000000-0000-0000-0000-000000000001'
\set admin  'ad000000-0000-0000-0000-000000000001'
insert into auth.users (id, email, raw_app_meta_data) values
  (:'admin', 'admin@example.com', '{}'),
  (:'device', 'device-1@devices.mcfly.invalid', '{"kind": "device"}');
insert into devices (id, user_id, name) values ('00000000-0000-0000-0000-00000000d001', :'device', 'Kitchen');

-- ───────────────────────────── What a board can pull from ─────────────────────────────
select tests.login(:'admin');
select tests.eq((select jsonb_array_length(admin_dashboard_sources()->'symbols')), 4, 'the symbols');
select tests.eq((select admin_dashboard_sources()->'symbols'->0->>'symbol'), 'SPY', 'in display order');
select tests.ok((select admin_dashboard_sources()->'metrics' @> '[{"key": "api.p95", "label": "API p95", "group": "Ops"}]'), 'the metrics, labelled and grouped');
select tests.ok((select admin_dashboard_sources()->'calendars' @> '["Work", "Home"]'), 'the calendars');
select tests.ok((select jsonb_array_length(admin_dashboard_sources()->'projects') >= 1), 'the projects');
select tests.ok((select jsonb_array_length(admin_dashboard_sources()->'news_sections') >= 1), 'the news sections');
select tests.ok((select admin_dashboard_sources()->'agents' @> '[{"name": "Grok", "has_key": true}]'), 'the agents');
select tests.eq((select admin_dashboard_sources()->>'timezone'), 'America/Chicago', 'the display''s time zone');

-- ───────────────────────────── Drawing ─────────────────────────────
-- Quotes: every visible symbol in order, or the ones picked, as tiles or a chart.
select tests.eq((select jsonb_agg(w->>'label') from jsonb_array_elements(admin_preview_dashboard('[{"from": "quotes"}]')) w),
                '["SPY", "AAPL", "NVDA", "TSLA"]'::jsonb, 'every symbol, in order');
select tests.eq((select admin_preview_dashboard('[{"from": "quotes", "symbols": ["nvda"]}]')->0),
                '{"type": "metric", "label": "NVDA", "value": 191.25, "unit": "USD", "delta": 2.85, "delta_pct": 1.51}'::jsonb, 'a quote as a tile');
select tests.eq((select admin_preview_dashboard('[{"from": "quotes", "symbols": ["AAPL"], "show": "chart"}]')->0),
                '{"type": "chart", "label": "Apple (AAPL)", "unit": "USD", "points": [245.12, 247.90]}'::jsonb, 'a quote as a chart, oldest first');
select tests.eq((select jsonb_array_length(admin_preview_dashboard('[{"from": "quotes", "limit": 2}]'))), 2, 'a limit');
select tests.eq((select admin_preview_dashboard('[{"from": "quotes", "symbols": ["ZZZZ"]}]')->0),
                '{"type": "text", "title": "Markets", "body": "No quotes yet for ZZZZ."}'::jsonb, 'nothing yet says so');

-- Metrics: picked keys, a group, or everything visible.
select tests.eq((select admin_preview_dashboard('[{"from": "metrics", "keys": ["api.p95"]}]')->0),
                '{"type": "metric", "label": "API p95", "value": 212, "unit": "ms", "delta": -18}'::jsonb, 'a metric, its newest value and label');
select tests.eq((select jsonb_agg(w->>'label') from jsonb_array_elements(admin_preview_dashboard('[{"from": "metrics", "group": "Ops"}]')) w),
                '["API p95", "Uptime"]'::jsonb, 'a group');
select tests.eq((select admin_preview_dashboard('[{"from": "metrics", "keys": ["api.p95"], "show": "chart"}]')->0->'points'),
                '[230, 212]'::jsonb, 'a metric''s history, oldest first');
select tests.eq((select admin_preview_dashboard('[{"from": "metrics", "keys": ["nope"], "title": "Shop"}]')->0),
                '{"type": "text", "title": "Shop", "body": "No numbers yet."}'::jsonb, 'an empty part keeps its title');

-- Projects: progress rings (a status when there's no progress), or one list.
select tests.eq((select admin_preview_dashboard('[{"from": "projects"}]')->0),
                '{"type": "progress", "label": "McFly", "value": 62, "max": 100, "unit": "%"}'::jsonb, 'a project''s progress');
select tests.eq((select admin_preview_dashboard('[{"from": "projects", "show": "list"}]')->0->>'type'), 'list', 'projects as a list');
select tests.ok((select admin_preview_dashboard('[{"from": "projects", "show": "list"}]')->0->'items' @> '["McFly · Ship the dashboards screen"]'),
                'with the next step');

-- The calendar: what hasn't ended yet, in the window, per calendar.
select tests.login_service();
select ingest_events(:'cal', jsonb_build_array(
  jsonb_build_object('id', 't-1', 'calendar', 'Clinic', 'title', 'Dentist', 'starts_at', now() + interval '3 days', 'ends_at', now() + interval '3 days 1 hour'),
  jsonb_build_object('id', 't-2', 'calendar', 'Clinic', 'title', 'Over already', 'starts_at', now() - interval '2 hours', 'ends_at', now() - interval '1 hour')));
select tests.login(:'admin');
select tests.eq((select admin_preview_dashboard('[{"from": "calendar", "calendars": ["Clinic"]}]')->0->>'title'), 'Next 7 days', 'a window''s title');
select tests.ok((select (admin_preview_dashboard('[{"from": "calendar", "calendars": ["Clinic"]}]')->0->'items'->>0) like '% · Dentist'),
                'an event, with its day and time');
select tests.eq((select jsonb_array_length(admin_preview_dashboard('[{"from": "calendar", "calendars": ["Clinic"]}]')->0->'items')), 1,
                'an event that ended is gone');
select tests.eq((select admin_preview_dashboard('[{"from": "calendar", "calendars": ["Clinic"], "days": 1}]')->0),
                '{"type": "text", "title": "Today", "body": "Nothing on the calendar."}'::jsonb, 'a shorter window');

-- Todos, the news, a brief, the agents, a note.
select tests.login_service();
select ingest_todos(:'grok', '[{"id": "t-a", "title": "Call the bank"}, {"id": "t-b", "title": "Done already", "done": true}]');
select tests.login(:'admin');
select tests.eq((select admin_preview_dashboard('[{"from": "todos"}]')->0), '{"type": "list", "title": "To do", "items": ["Call the bank"]}'::jsonb, 'open todos');
select tests.eq((select admin_preview_dashboard('[{"from": "todos", "kind": "reminder"}]')->0->>'body'), 'No reminders set.', 'no reminders');
select tests.eq((select admin_preview_dashboard('[{"from": "news", "limit": 2}]')->0->>'type'), 'list', 'the headlines');
select tests.eq((select jsonb_array_length(admin_preview_dashboard('[{"from": "news", "limit": 2}]')->0->'items')), 2, 'as many as asked');
select tests.eq((select admin_preview_dashboard('[{"from": "brief", "kind": "daily"}]')->0->>'title'), 'Morning briefing', 'the newest daily brief');
select tests.eq((select admin_preview_dashboard('[{"from": "brief"}]')->0->>'title'), 'Hourly check-in', 'the newest of any kind');
select tests.eq((select admin_preview_dashboard('[{"from": "agents", "agents": ["00000000-0000-0000-0000-00000000a001"]}]')->0->>'state'), 'ok',
                'an agent that pushed lately is fine');
select tests.eq((select admin_preview_dashboard('[{"from": "agents", "agents": ["00000000-0000-0000-0000-00000000a004"]}]')->0),
                '{"type": "status", "label": "GitHub watcher", "state": "unknown", "detail": "No pushes yet"}'::jsonb, 'one that never pushed');
select tests.eq((select admin_preview_dashboard('[{"from": "note", "title": "Hi", "body": "Hello there"}]')->0),
                '{"type": "text", "title": "Hi", "body": "Hello there"}'::jsonb, 'a note');
-- A part that can't be drawn says so; the rest of the board still draws.
select tests.eq((select admin_preview_dashboard('[{"from": "quotes", "limit": 99999999999}, {"from": "note", "body": "still here"}]')),
                '[{"type": "text", "title": "This part", "body": "Could not be drawn just now."}, {"type": "text", "body": "still here"}]'::jsonb,
                'a broken part');
select tests.eq((select jsonb_array_length(admin_preview_dashboard(
                   (select jsonb_agg(jsonb_build_object('from', 'quotes', 'limit', 12)) from generate_series(1, 20))))), 40, 'at most 40 widgets');

-- Recipes the console may not store.
select tests.throws($$select admin_preview_dashboard('[]')$$, 'a dashboard needs at least one part', 'no parts');
select tests.throws($$select admin_preview_dashboard('[{"from": "weather"}]')$$, 'a part pulls from %', 'an unknown source');
select tests.throws($$select admin_preview_dashboard('[{"from": "quotes", "symbols": "AAPL"}]')$$, 'a part''s symbols must be a list', 'not a list');
select tests.throws($$select admin_preview_dashboard('[{"from": "note"}]')$$, 'a note needs some words', 'an empty note');
select tests.throws($$select admin_preview_dashboard((select jsonb_agg('{"from": "todos"}'::jsonb) from generate_series(1, 21)))$$,
                    'at most 20 parts on a dashboard', 'too many parts');

-- ───────────────────────────── Making and editing ─────────────────────────────
select admin_save_dashboard(null, 'My Markets!', '[{"from": "quotes", "symbols": ["AAPL", "NVDA"]}]', 'What I hold', 'markets') as made \gset
select tests.eq((select row(d.key, d.title, d.subtitle, d.template, a.slug, jsonb_array_length(d.widgets))::text
                   from dashboards d join agents a on a.id = d.agent_id where d.id = :'made'),
                row('my-markets', 'My Markets!', 'What I hold', 'markets', 'mcfly-assistant', 2)::text, 'made, keyed from its title, as McFly');
select admin_save_dashboard(null, 'My markets', '[{"from": "todos"}]') as second \gset
select tests.eq((select key from dashboards where id = :'second'), 'my-markets-2', 'a unique key');
select tests.eq((select template from admin_list_dashboards() where id = :'made'), 'markets', 'the list has the template');
select tests.eq((select sources from admin_list_dashboards() where key = 'ops'), null::jsonb, 'and null for an agent''s board');
select tests.eq((select action from admin_audit_log order by id desc limit 1), 'create_dashboard', 'audited');

select admin_save_dashboard(:'made', 'Holdings', '[{"from": "quotes", "symbols": ["TSLA"]}]');
select tests.eq((select row(key, title, subtitle, template, widgets->0->>'label')::text from dashboards where id = :'made'),
                row('my-markets', 'Holdings', null, 'markets', 'TSLA')::text, 'edited: the key and template stay');
select id as agents_board from dashboards where key = 'ops' \gset
select tests.throws(format($$select admin_save_dashboard(%L, 'x', '[{"from": "todos"}]')$$, :'agents_board'),
                    'an agent lays this dashboard out%', 'an agent''s board is not edited here');
select tests.throws($$select admin_save_dashboard('99999999-9999-9999-9999-999999999999', 'x', '[{"from": "todos"}]')$$, 'dashboard not found', 'unknown board');
select tests.throws($$select admin_save_dashboard(null, '  ', '[{"from": "todos"}]')$$, 'give the dashboard a title', 'no title');
select admin_set_dashboard(:'made', sort_order => 3);
select tests.eq((select sort_order from dashboards where id = :'made'), 3, 'ordered like any board');

-- ───────────────────────────── Redrawing ─────────────────────────────
-- A push redraws the boards that pull from it, at the end of the push.
select tests.login_service();
select ingest_quotes(:'stocks', '[{"symbol": "TSLA", "price": 410.5, "change": 8.4, "change_pct": 2.09}]');
select tests.eq((select (widgets->0->>'value')::numeric from dashboards where id = :'made'), 410.5, 'a quote push redraws');
select ingest_todos(:'grok', '[{"id": "t-c", "title": "Book flights"}]');
select tests.ok((select widgets->0->'items' @> '["Book flights"]' from dashboards where key = 'my-markets-2'), 'a todo push redraws');
select tests.eq((select jsonb_array_length(widgets) from dashboards where key = 'ops'), 8, 'an agent''s board is left alone');

-- A redraw that fails is never the pusher's problem.
select tests.logout();
alter function public.render_made_dashboards() rename to render_made_dashboards_real;
create function public.render_made_dashboards() returns int language plpgsql as $$ begin raise exception 'boom'; end $$;
select tests.login_service();
select tests.eq(ingest_quotes(:'stocks', '[{"symbol": "TSLA", "price": 420}]'), 1, 'the push still lands');
select tests.eq((select price from quotes_latest where symbol = 'TSLA'), 420::numeric, 'and is kept');
select tests.logout();
drop function public.render_made_dashboards();
alter function public.render_made_dashboards_real() rename to render_made_dashboards;

-- An agent can't push over a made board; its other boards still go in.
select tests.login_service();
select tests.throws($$select ingest_dashboards('00000000-0000-0000-0000-00000000a005', '[{"key": "my-markets", "widgets": [{"type": "text", "body": "mine"}]}]')$$,
                    'dashboard my-markets is made in the console%', 'a made board''s key is taken');
select tests.eq(ingest_dashboards(:'ops', '[{"key": "fresh", "widgets": [{"type": "text", "body": "new"}]}]'), 1, 'another key is fine');

-- ───────────────────────────── Who sees what ─────────────────────────────
select tests.login(:'device');
select tests.eq((select title from dashboards where key = 'my-markets'), 'Holdings', 'a display reads a made board');
select tests.eq((select widgets->0->>'label' from dashboards where key = 'my-markets'), 'TSLA', 'drawn, like any board');
select tests.throws($$select admin_preview_dashboard('[{"from": "quotes"}]')$$, 'admin only', 'a display can''t draw a recipe');
select tests.throws($$select dashboard_widgets('[{"from": "quotes"}]')$$, '%permission denied%', 'or call the drawing directly');
select tests.throws($$select render_made_dashboards()$$, '%permission denied%', 'or redraw');
select tests.throws($$select admin_save_dashboard(null, 'x', '[{"from": "todos"}]')$$, 'admin only', 'or make a board');
select tests.login(null);
select tests.eq((select count(*)::int from dashboards), 0, 'anon sees no boards');
select tests.throws($$select admin_dashboard_sources()$$, '%permission denied%', 'or what they pull from');
