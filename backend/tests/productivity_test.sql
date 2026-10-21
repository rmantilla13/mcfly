-- The productivity feeds: projects and their updates, metrics, dashboards
-- and calendar events: ingest, what displays see, the admin RPCs, retention.
\set ON_ERROR_STOP 1
\set gh   '00000000-0000-0000-0000-00000000a004'
\set ops  '00000000-0000-0000-0000-00000000a005'
\set cal  '00000000-0000-0000-0000-00000000a006'
\set device 'd0000000-0000-0000-0000-000000000001'
\set admin  'ad000000-0000-0000-0000-000000000001'
insert into auth.users (id, email, raw_app_meta_data) values
  (:'admin', 'admin@example.com', '{}'),
  (:'device', 'device-1@devices.mcfly.invalid', '{"kind": "device"}');
insert into devices (id, user_id, name) values ('00000000-0000-0000-0000-00000000d001', :'device', 'Kitchen');

-- ───────────────────────────── Displays read ─────────────────────────────
select tests.login(:'device');
select tests.eq((select count(*)::int from projects), 3, 'device reads projects');
select tests.eq((select count(*)::int from project_updates), 3, 'device reads project updates');
select tests.eq((select count(*)::int from metrics_latest), 5, 'device reads the latest metrics');
select tests.eq((select count(*)::int from metrics), 8, 'and their history');
select tests.eq((select count(*)::int from dashboards), 2, 'device reads dashboards');
select tests.eq((select count(*)::int from events), 6, 'device reads events');
select tests.eq((select assistant_provider from platform_settings), 'claude', 'the assistant provider is in the settings');
select tests.throws($$insert into projects (agent_id, key, name) values ('00000000-0000-0000-0000-00000000a004', 'x', 'x')$$,
                    '%row-level security%', 'device cannot write projects');
select tests.eq(tests.affected($$delete from events$$), 0, 'device cannot delete events');
select tests.login(null);
select tests.eq((select count(*)::int from projects) + (select count(*)::int from metrics) + (select count(*)::int from dashboards)
                + (select count(*)::int from events), 0, 'anon sees nothing');

-- ───────────────────────────── Projects ─────────────────────────────
select tests.login_service();
select tests.eq((select row(name, status, progress, next_step)::text from projects where key = 'mcfly'),
                row('McFly', 'active', 62, 'Ship the dashboards screen')::text, 'seeded project');
select tests.eq(ingest_projects(:'gh', '[{"key": "mcfly", "name": "McFly v2", "status": "done", "progress": 100,
                                        "updates": [{"kind": "deploy", "text": "Shipped 1.0", "at": "2026-10-15T00:00:00Z"},
                                                    {"kind": "ci", "text": "CI green on main (14 checks)", "at": "2026-10-14T19:40:00Z"}]}]'), 1, 're-push');
select tests.eq((select row(name, status, progress, next_step, summary)::text from projects where key = 'mcfly'),
                row('McFly v2', 'done', 100, null, '')::text, 'replaced in place; absent fields clear');
select tests.eq((select count(*)::int from project_updates u join projects p on p.id = u.project_id where p.key = 'mcfly'), 3,
                'a repeated update line is not added twice');
select tests.eq((select u.kind from project_updates u join projects p on p.id = u.project_id where p.key = 'mcfly' order by u.happened_at desc limit 1),
                'deploy', 'the newest update');
select tests.throws($$select ingest_projects('00000000-0000-0000-0000-00000000a004', '[{"key": "bad key!", "name": "x"}]')$$, '%check constraint%', 'bad key');
select tests.throws($$select ingest_projects('00000000-0000-0000-0000-00000000a004', '[{"key": "k", "name": "x", "status": "flying"}]')$$, '%check constraint%', 'bad status');
-- Planned (20261021000060): lined up, not started; up next after the ones in flight.
select tests.eq(ingest_projects(:'ops', '[{"key": "next-thing", "name": "Next thing", "status": "planned"}]'), 1, 'a planned project');
select tests.eq((select status from projects where key = 'next-thing'), 'planned', 'planned is a status');
delete from projects where key = 'next-thing';
select tests.throws($$select ingest_projects('00000000-0000-0000-0000-00000000a004', '[{"key": "k", "name": "x", "progress": 120}]')$$, '%check constraint%', 'progress over 100');
select tests.throws($$select ingest_projects('00000000-0000-0000-0000-00000000a004', '{"key": "k"}')$$, 'projects must be a list', 'not a list');
-- A second agent may use the same key: projects are per agent.
select tests.eq(ingest_projects(:'ops', '[{"key": "mcfly", "name": "Other McFly"}]'), 1, 'same key, other agent');
select tests.eq((select count(*)::int from projects where key = 'mcfly'), 2, 'two rows');

-- Stages (20261021000050): the seed's, kept by the push above, which sent none.
\set mine 'from projects where key = ''mcfly'' and agent_id = ''00000000-0000-0000-0000-00000000a004'''
select tests.eq((select row(stages, stage)::text :mine), row('["Plan", "Build", "Review", "Ship"]'::jsonb, 'Build')::text, 'a push without stages keeps them');
select stage_since as since0 :mine \gset
select tests.ok(:'since0' <> '', 'the seed''s stage has a time');
-- A stage in any case lands as the stage's own name, at the time it moved.
select tests.eq(ingest_projects(:'gh', '[{"key": "mcfly", "name": "McFly v2", "status": "done", "stage": " review "}]'), 1, 'move on a stage');
select tests.eq((select stage :mine), 'Review', 'the stage''s own name');
select stage_since as since1 :mine \gset
select tests.ok(:'since1'::timestamptz <> :'since0'::timestamptz, 'stage_since moves with the stage');
select ingest_projects(:'gh', '[{"key": "mcfly", "name": "McFly v2", "status": "done", "stage": "Review"}]');
select tests.eq((select stage_since :mine), :'since1'::timestamptz, 'the same stage again keeps its time');
-- New stages keep the stage when they still name it, and clear it when not.
select ingest_projects(:'gh', '[{"key": "mcfly", "name": "McFly v2", "status": "done", "stages": [" Plan ", "Review", "Ship"]}]');
select tests.eq((select row(stages, stage, stage_since)::text :mine), row('["Plan", "Review", "Ship"]'::jsonb, 'Review', :'since1'::timestamptz)::text,
                'new stages, trimmed, keep the stage they still name');
select ingest_projects(:'gh', '[{"key": "mcfly", "name": "McFly v2", "status": "done", "stages": ["Plan", "Ship"]}]');
select tests.eq((select row(stage, stage_since)::text :mine), row(null::text, null::timestamptz)::text, 'and drop one they don''t');
select ingest_projects(:'gh', '[{"key": "mcfly", "name": "McFly v2", "status": "done", "stage": "ship"}]');
select ingest_projects(:'gh', '[{"key": "mcfly", "name": "McFly v2", "status": "done", "stage": null}]');
select tests.eq((select row(stages, stage)::text :mine), row('["Plan", "Ship"]'::jsonb, null::text)::text, 'a null stage clears it, not the stages');
select ingest_projects(:'gh', '[{"key": "mcfly", "name": "McFly v2", "status": "done", "stages": ["Plan", "Ship"], "stage": "Ship"}]');
select ingest_projects(:'gh', '[{"key": "mcfly", "name": "McFly v2", "status": "done", "stages": []}]');
select tests.eq((select row(stages, stage)::text :mine), row('[]'::jsonb, null::text)::text, 'no stages clears both');
select ingest_projects(:'gh', '[{"key": "mcfly", "name": "McFly v2", "status": "done", "stages": ["Plan", "Build", "Review", "Ship"], "stage": "Ship"}]');
select tests.throws($$select ingest_projects('00000000-0000-0000-0000-00000000a004', '[{"key": "mcfly", "name": "x", "stage": "Launch"}]')$$,
                    'project mcfly: stage "Launch" is not one of its stages', 'a stage that isn''t listed');
select tests.throws($$select ingest_projects('00000000-0000-0000-0000-00000000a004', '[{"key": "fresh", "name": "x", "stage": "Build"}]')$$,
                    'project fresh: a stage needs stages to be one of', 'a stage without stages');
select tests.throws($$select ingest_projects('00000000-0000-0000-0000-00000000a004', '[{"key": "k", "name": "x", "stages": "Plan, Build"}]')$$,
                    'project k: stages must be a list of names', 'stages not a list');
select tests.throws($$select ingest_projects('00000000-0000-0000-0000-00000000a004', '[{"key": "k", "name": "x", "stages": ["1","2","3","4","5","6","7","8","9","10","11","12","13"]}]')$$,
                    'project k: at most 12 stages', 'too many stages');
select tests.throws($$select ingest_projects('00000000-0000-0000-0000-00000000a004', '[{"key": "k", "name": "x", "stages": ["Plan", " "]}]')$$,
                    'project k: each stage must be a name of 1 to 40 characters', 'a blank stage');
select tests.throws($$select ingest_projects('00000000-0000-0000-0000-00000000a004', '[{"key": "k", "name": "x", "stages": ["Plan", 2]}]')$$,
                    'project k: each stage must be a name of 1 to 40 characters', 'a stage that isn''t text');
select tests.throws($$select ingest_projects('00000000-0000-0000-0000-00000000a004', '[{"key": "k", "name": "x", "stages": ["Plan", "plan"]}]')$$,
                    'project k: stage "plan" is listed twice', 'a stage twice');
-- The table checks them too, whoever writes.
select tests.throws($$update projects set stage = 'Nope' where key = 'mcfly'$$, '%check constraint%', 'the stage must be listed');
select tests.throws($$update projects set stages = '["a", "A"]' where key = 'mcfly'$$, '%check constraint%', 'stages stay distinct');
select tests.eq((select count(*)::int from projects where key in ('fresh', 'k')), 0, 'failed pushes add nothing');

-- ───────────────────────────── Metrics ─────────────────────────────
select tests.eq((select value from metrics_latest where key = 'sales.today'), 4280::numeric, 'newest value');
select tests.eq((select label from metric_settings where key = 'api.p95'), 'API p95', 'label kept');
select tests.eq(ingest_metrics(:'ops', '[{"key": "Sales.Today", "value": "5100", "unit": "USD", "as_of": "2027-01-01T00:00:00Z"}]'), 1, 'one metric');
select tests.eq((select value from metrics_latest where key = 'sales.today'), 5100::numeric, 'key lower-cased, number from a string');
select tests.eq((select label from metric_settings where key = 'sales.today'), 'Sales today', 'a push without a label keeps the old one');
select tests.throws($$select ingest_metrics('00000000-0000-0000-0000-00000000a005', '[{"key": "no value"}]')$$, 'metric key % is not usable', 'bad key');
select tests.throws($$select ingest_metrics('00000000-0000-0000-0000-00000000a005', '[{"key": "x"}]')$$, 'metric x has no value', 'no value');

-- ───────────────────────────── Dashboards ─────────────────────────────
select tests.eq((select jsonb_array_length(widgets) from dashboards where key = 'ops'), 8, 'seeded dashboard');
select tests.eq(ingest_dashboards(:'gh', '[{"key": "OPS", "title": "Ops v2", "widgets": [{"type": "text", "title": "t", "body": "b"}]}]'), 1, 're-push by key');
select tests.eq((select row(title, jsonb_array_length(widgets), agent_id)::text from dashboards where key = 'ops'),
                row('Ops v2', 1, :'gh'::uuid)::text, 'replaced whole, by the new agent');
select tests.throws($$select ingest_dashboards('00000000-0000-0000-0000-00000000a005', '[{"key": "x", "widgets": []}]')$$, '%check constraint%', 'no widgets');
select tests.throws($$select ingest_dashboards('00000000-0000-0000-0000-00000000a005', '[{"key": "x", "widgets": [{"type": "video"}]}]')$$,
                    'dashboard x: each widget needs a type%', 'unknown widget');
select tests.throws($$select ingest_dashboards('00000000-0000-0000-0000-00000000a005', '[{"key": "x"}]')$$, 'dashboard x needs widgets', 'missing widgets');

-- ───────────────────────────── Events ─────────────────────────────
select tests.eq((select count(*)::int from events where calendar = 'Work'), 3, 'seeded work events');
select tests.eq((select ends_at - starts_at from events where external_id = 'ev-6'), interval '23 hours 59 minutes 59 seconds', 'all-day event spans the day');
-- The whole Work calendar again, with one event gone and one new.
select tests.eq(ingest_events(:'cal', '[{"id": "ev-1", "title": "Standup (moved)", "starts_at": "2026-10-14T15:00:00Z"},
                                      {"id": "ev-7", "title": "Retro", "starts_at": "2026-10-16T20:00:00Z"}]', 'Work'), 2, 'replace a calendar');
select tests.eq((select count(*)::int from events where calendar = 'Work'), 2, 'removed events are gone');
select tests.eq((select row(title, ends_at - starts_at)::text from events where external_id = 'ev-1'), row('Standup (moved)', interval '1 hour')::text,
                'updated in place; an hour by default');
select tests.eq((select count(*)::int from events where calendar = 'Home'), 3, 'other calendars untouched');
-- Without an id, the title and start identify the event.
select tests.eq(ingest_events(:'cal', '[{"calendar": "Home", "title": "Gym", "starts_at": "2026-10-16T12:00:00Z"}]'), 1, 'no id');
select tests.eq(ingest_events(:'cal', '[{"calendar": "Home", "title": "Gym", "starts_at": "2026-10-16T12:00:00Z"}]'), 1, 'again');
select tests.eq((select count(*)::int from events where title = 'Gym'), 1, 'the same event once');
select tests.throws($$select ingest_events('00000000-0000-0000-0000-00000000a006', '[{"title": "x"}]')$$, 'event x needs starts_at', 'no start');
select tests.throws($$select ingest_events('00000000-0000-0000-0000-00000000a006', '[{"title": "x", "starts_at": "2026-01-02T00:00:00Z", "ends_at": "2026-01-01T00:00:00Z"}]')$$,
                    '%check constraint%', 'ends before it starts');

-- ───────────────────────────── Admin ─────────────────────────────
select tests.login(:'admin');
select tests.eq((select count(*)::int from admin_list_projects()), 4, 'lists projects');
select tests.eq((select name from admin_list_projects() limit 1), 'Onyx', 'done projects sort last');
select tests.eq((select last_update from admin_list_projects() where key = 'mcfly' and agent_name = 'GitHub watcher'), 'Shipped 1.0', 'last update');
select tests.eq((select row(stages, stage, stage_since is not null)::text from admin_list_projects() where key = 'mcfly' and agent_name = 'GitHub watcher'),
                row('["Plan", "Build", "Review", "Ship"]'::jsonb, 'Ship', true)::text, 'with its stages');
select tests.eq((select row(stages, stage)::text from admin_list_projects() where key = 'mcfly' and agent_name = 'Ops metrics'),
                row('[]'::jsonb, null::text)::text, 'none for a project without');
select id as proj from admin_list_projects() where key = 'onyx' \gset
select tests.eq((select count(*)::int from admin_project_updates(:'proj')), 1, 'project updates');
select admin_delete_project(:'proj');
select tests.eq((select count(*)::int from projects where key = 'onyx'), 0, 'deleted');
select tests.throws($$select admin_delete_project('99999999-9999-9999-9999-999999999999')$$, 'project not found', 'unknown project');

select tests.eq((select count(*)::int from admin_list_metrics()), 5, 'lists metrics');
select tests.eq((select history_count from admin_list_metrics() where key = 'sales.today'), 3, 'history count');
select admin_set_metric('sales.today', hidden => true, sort_order => 5, group_name => 'Shop');
select tests.eq((select row(hidden, sort_order, group_name)::text from metric_settings where key = 'sales.today'), row(true, 5, 'Shop')::text, 'metric settings');
select admin_delete_metric('steps');
select tests.eq((select count(*)::int from metrics where key = 'steps'), 0, 'metric rows gone');
select tests.throws($$select admin_delete_metric('nope')$$, 'metric not found', 'unknown metric');

select tests.eq((select count(*)::int from admin_list_dashboards()), 2, 'lists dashboards');
select id as dash from admin_list_dashboards() where key = 'launch' \gset
select admin_set_dashboard(:'dash', hidden => true);
select tests.eq((select hidden from dashboards where key = 'launch'), true, 'dashboard hidden');
select admin_delete_dashboard(:'dash');
select tests.eq((select count(*)::int from dashboards), 1, 'dashboard deleted');

select tests.ok((select count(*) from admin_list_events(30, 60)) >= 5, 'lists events');
select id as ev from admin_list_events(30, 60) where title = 'Gym' \gset
select admin_delete_event(:'ev');
select tests.eq((select count(*)::int from events where title = 'Gym'), 0, 'event deleted');
select tests.eq(admin_delete_calendar(:'cal', 'Home'), 3, 'a calendar removed whole');
select tests.eq((select count(*)::int from events), 2, 'only Work left');

select tests.eq(admin_update_settings(assistant_provider => 'grok', metrics_keep_days => 7)->>'assistant_provider', 'grok', 'provider set');
select tests.throws($$select admin_update_settings(assistant_provider => 'siri')$$, 'assistant_provider must be claude or grok', 'bad provider');
select tests.eq((admin_overview()->>'projects')::int, 2, 'overview counts open projects');
select tests.eq((admin_overview()->>'dashboards')::int, 1, 'and dashboards');
select tests.ok((select count(*) from admin_list_audit()) >= 8, 'changes audited');

-- ───────────────────────────── Retention ─────────────────────────────
select tests.logout();
update metrics set as_of = now() - interval '30 days' where key = 'api.p95' and value = 230;
update events set starts_at = now() - interval '100 days', ends_at = now() - interval '100 days' where external_id = 'ev-7';
select tests.login_service();
select prune_feed() as pruned \gset
select tests.eq(((:'pruned')::jsonb->>'metrics')::int, 1, 'old metric history pruned (7 days)');
select tests.eq(((:'pruned')::jsonb->>'events')::int, 1, 'old events pruned');
select tests.eq((select count(*)::int from metrics where key = 'api.p95'), 1, 'the newest metric stays');
