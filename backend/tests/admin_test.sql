-- admin_* RPCs: refuse everyone but platform admins (and the service role),
-- work for admins, and leave an audit trail for every change.
\set ON_ERROR_STOP 1
\set grok     '00000000-0000-0000-0000-00000000a001'
\set stocks   '00000000-0000-0000-0000-00000000a002'
\set pulse    '00000000-0000-0000-0000-00000000a003'
\set device   'd0000000-0000-0000-0000-000000000001'
\set stranger 'e0000000-0000-0000-0000-000000000001'
\set admin    'ad000000-0000-0000-0000-000000000001'
\set admin2   'ad000000-0000-0000-0000-000000000002'

-- The first person to sign up is the admin (accounts_test); the rest are not.
insert into auth.users (id, email, raw_app_meta_data) values
  (:'admin', 'admin@example.com', '{}'),
  (:'device', 'device-1@devices.mcfly.invalid', '{"kind": "device"}'),
  (:'stranger', 'stranger@example.com', '{}'),
  (:'admin2', 'admin2@example.com', '{}');
insert into devices (id, user_id, name) values ('00000000-0000-0000-0000-00000000d001', :'device', 'Kitchen');

create table tests.admin_calls (sql text);
insert into tests.admin_calls values
  ('select admin_overview()'),
  ('select * from admin_list_agents()'),
  ('select * from admin_create_agent(''X'')'),
  (format('select admin_rotate_agent_key(%L)', :'grok')),
  (format('select admin_update_agent(%L, ''Y'')', :'grok')),
  (format('select admin_revoke_agent(%L)', :'grok')),
  (format('select admin_delete_agent(%L)', :'grok')),
  ('select * from admin_list_briefs()'),
  ('select admin_delete_brief(''99999999-9999-9999-9999-999999999999'')'),
  ('select * from admin_list_quotes()'),
  ('select admin_set_symbol(''AAPL'', true)'),
  ('select admin_delete_symbol(''AAPL'')'),
  ('select * from admin_list_news_reports()'),
  ('select admin_news_report(''99999999-9999-9999-9999-999999999999'')'),
  ('select admin_delete_news_report(''99999999-9999-9999-9999-999999999999'')'),
  ('select * from admin_list_ingest()'),
  ('select * from admin_list_devices()'),
  ('select admin_rename_device(''00000000-0000-0000-0000-00000000d001'', ''x'')'),
  ('select admin_revoke_device(''00000000-0000-0000-0000-00000000d001'')'),
  ('select admin_get_settings()'),
  ('select admin_update_settings(display_name => ''x'')'),
  (format('select admin_set_admin(%L, true)', :'stranger')),
  ('select * from admin_list_audit()'),
  ('select prune_feed()'),
  ('select admin_backend_status()');
grant select on tests.admin_calls to anon, authenticated;

select tests.ok(not has_function_privilege('anon', 'admin_overview()', 'execute'), 'anon cannot call admin RPCs');
select tests.ok(has_function_privilege('authenticated', 'admin_overview()', 'execute'), 'authenticated may call (checked inside)');
select tests.ok(not has_function_privilege('authenticated', 'log_admin_action(text, text, text, jsonb)', 'execute'), 'audit writer is internal');
select tests.ok(not has_function_privilege('authenticated', 'new_agent_key()', 'execute'), 'key maker is internal');
select tests.ok(not has_function_privilege('authenticated', 'ingest_news(uuid, jsonb)', 'execute'), 'ingest is internal');

select tests.login(:'stranger');
select tests.throws(sql, 'admin only', 'stranger: ' || sql) from tests.admin_calls;
select tests.login(:'device');
select tests.throws(sql, 'admin only', 'display: ' || sql) from tests.admin_calls;
select tests.login(null);
select tests.throws(sql, 'permission denied%', 'anon: ' || sql) from tests.admin_calls;

select tests.logout();
select tests.eq((select count(*)::int from admin_audit_log), 0, 'refused calls left no audit rows');
select tests.login(:'admin');

-- ───────────────────────────── Agents ─────────────────────────────
select id as new_agent, slug as new_slug, key as new_key from admin_create_agent('  Weather Bot  ', 'other', '#123ABC') \gset
select tests.eq(:'new_slug'::text, 'weather-bot'::text, 'slug from the name');
select tests.ok(:'new_key' ~ '^mcf_[0-9a-f]{40}$', 'key shape');
select tests.eq((select row(name, kind, color)::text from agents where id = :'new_agent'), row('Weather Bot', 'other', '#123ABC')::text, 'stored trimmed');
select tests.eq((select count(*)::int from agent_keys), 0, 'admins never read the key table');
select tests.login_service();
select tests.eq((select key_prefix from agent_keys where agent_id = :'new_agent'), left(:'new_key', 12), 'prefix kept for the console');
select tests.eq((select name from agent_for_key(key_hash(:'new_key'))), 'Weather Bot', 'the key finds the agent');
select tests.login(:'admin');
select tests.ok(not exists (select 1 from admin_audit_log where details::text like '%' || :'new_key' || '%'), 'the key is not in the audit log');
select tests.eq((select details->>'slug' from admin_audit_log where action = 'create_agent'), 'weather-bot', 'creation audited');
select slug as dup_slug from admin_create_agent('Weather Bot') \gset
select tests.eq(:'dup_slug'::text, 'weather-bot-1'::text, 'a second agent with the same name gets a numbered slug');
select tests.throws($$select * from admin_create_agent('')$$, 'name must be 1 to 80 characters', 'empty name');
select tests.throws($$select * from admin_create_agent('x', 'bad-kind')$$, '%check constraint%', 'unknown kind');
select tests.eq((select key_prefix from admin_list_agents() where id = :'new_agent'), left(:'new_key', 12), 'list shows the prefix');

select admin_rotate_agent_key(:'new_agent') as rotated \gset
select tests.ok(:'rotated' <> :'new_key', 'a new key');
select tests.login_service();
select tests.eq((select count(*)::int from agent_for_key(key_hash(:'new_key'))), 0, 'the old key is dead');
select tests.eq((select name from agent_for_key(key_hash(:'rotated'))), 'Weather Bot', 'the new key works');
select tests.login(:'admin');

select admin_update_agent(:'new_agent', name => 'Weather', color => '#000000');
select tests.eq((select row(name, kind, color)::text from agents where id = :'new_agent'), row('Weather', 'other', '#000000')::text, 'renamed; kind kept');
select tests.throws($$select admin_update_agent('99999999-9999-9999-9999-999999999999', 'x')$$, 'agent not found', 'unknown agent');

select admin_revoke_agent(:'new_agent');
select tests.ok((select revoked_at is not null from agents where id = :'new_agent'), 'revoked');
select tests.login_service();
select tests.eq((select count(*)::int from agent_keys where agent_id = :'new_agent'), 0, 'its key is gone');
select tests.eq((select count(*)::int from agent_for_key(key_hash(:'rotated'))), 0, 'a revoked agent cannot push');
select tests.login(:'admin');
select admin_rotate_agent_key(:'new_agent') as revived \gset
select tests.ok((select revoked_at is null from agents where id = :'new_agent'), 'a new key un-revokes');

select admin_delete_agent(:'grok');
select tests.eq((select count(*)::int from agents where id = :'grok'), 0, 'deleted');
select tests.eq((select count(*)::int from briefs where agent_id = :'grok'), 0, 'its briefs went with it');
select tests.eq((select count(*)::int from ingest_log where agent_id = :'grok'), 0, 'and its log rows');
select tests.throws($$select admin_delete_agent('99999999-9999-9999-9999-999999999999')$$, 'agent not found', 'delete unknown');

-- ───────────────────────────── Feeds ─────────────────────────────
select tests.login_service();
select ingest_briefs(:'stocks', '[{"id": "b1", "title": "Market close", "body": "Up."}]');
select tests.login(:'admin');
select id as brief from admin_list_briefs(1, 0) \gset
select tests.eq((select title from admin_list_briefs(1, 0)), 'Market close', 'newest brief first');
select tests.eq((select agent_name from admin_list_briefs(1, 0)), 'Market desk', 'with its agent');
select admin_delete_brief(:'brief');
select tests.eq((select count(*)::int from briefs where id = :'brief'), 0, 'brief deleted');
select tests.throws($$select admin_delete_brief('99999999-9999-9999-9999-999999999999')$$, 'brief not found', 'delete unknown brief');

select tests.eq((select symbol from admin_list_quotes() limit 1), 'SPY', 'quotes in display order');
select tests.eq((select history_count from admin_list_quotes() where symbol = 'AAPL'), 2, 'history count');
select admin_set_symbol('aapl', hidden => true, sort_order => 50, name => 'Apple Inc.');
select tests.eq((select row(hidden, sort_order, name)::text from symbols where symbol = 'AAPL'), row(true, 50, 'Apple Inc.')::text, 'symbol settings');
select tests.eq((select symbol from admin_list_quotes() order by hidden desc limit 1), 'AAPL', 'hidden symbols sort last');
select tests.throws($$select admin_set_symbol('ZZZZ', true)$$, 'symbol not found', 'unknown symbol');
select admin_delete_symbol('NVDA');
select tests.eq((select count(*)::int from quotes where symbol = 'NVDA'), 0, 'quotes gone with the symbol');
select tests.eq((select details->>'quotes_removed' from admin_audit_log where action = 'delete_symbol'), '2', 'audited with the count');

select id as report from admin_list_news_reports() \gset
select tests.eq((select item_count from admin_list_news_reports()), 6, 'report item count');
select tests.eq((select sections from admin_list_news_reports()), '{"AI Tech","Paid Ads",Social}'::text[], 'section names');
select tests.eq(jsonb_array_length(admin_news_report(:'report')->'items'), 6, 'report detail');
select tests.eq(admin_news_report(:'report')->'items'->0->>'item_key', 'reels', 'items in order');
select admin_delete_news_report(:'report');
select tests.eq((select count(*)::int from news_items), 0, 'items gone with the report');
select tests.throws($$select admin_news_report('99999999-9999-9999-9999-999999999999')$$, 'report not found', 'unknown report');

-- ───────────────────────────── Displays ─────────────────────────────
select tests.eq((select name from admin_list_devices()), 'Kitchen', 'lists displays');
select admin_rename_device('00000000-0000-0000-0000-00000000d001', ' Hallway ');
select tests.eq((select name from devices), 'Hallway', 'renamed and trimmed');
select tests.throws($$select admin_rename_device('00000000-0000-0000-0000-00000000d001', ' ')$$, 'name is required', 'empty name');
select admin_revoke_device('00000000-0000-0000-0000-00000000d001') as revoked \gset
select tests.eq((select count(*)::int from devices), 0, 'display removed');
select tests.eq((:'revoked')::jsonb->>'user_id', :'device', 'its auth user is named for cleanup');
select tests.throws($$select admin_revoke_device('00000000-0000-0000-0000-00000000d001')$$, 'device not found', 'revoke twice');

-- ───────────────────────────── Settings ─────────────────────────────
select tests.eq(admin_get_settings() - 'updated_at' - 'updated_by',
                '{"display_name": "McFly", "timezone": "America/Chicago", "briefs_keep_days": 30, "quotes_keep_days": 90, "news_keep_reports": 14,
                  "assistant_provider": "claude", "metrics_keep_days": 90, "events_keep_days": 60}'::jsonb,
                'defaults');
select tests.eq(admin_update_settings(display_name => 'Doc', briefs_keep_days => 7)->>'briefs_keep_days', '7', 'changed');
select tests.eq(admin_get_settings()->>'display_name', 'Doc', 'renamed');
select tests.eq(admin_update_settings()->>'display_name', 'Doc', 'no arguments: no change');
select tests.throws($$select admin_update_settings(timezone => 'Mars/Olympus')$$, 'timezone % is not known', 'bad timezone');
select tests.eq(admin_update_settings(timezone => 'America/New_York')->>'timezone', 'America/New_York', 'a real timezone');
select tests.throws($$select admin_update_settings(news_keep_reports => 0)$$, '%check constraint%', 'keep at least one report');
select tests.eq((select details from admin_audit_log where action = 'update_settings' order by id limit 1),
                '{"display_name": "Doc", "briefs_keep_days": 7}'::jsonb, 'audit records the change');

-- ───────────────────────────── Admins ─────────────────────────────
select tests.throws(format('select admin_set_admin(%L, false)', :'admin'), 'the last admin can''t be removed', 'last admin stays');
select admin_set_admin(:'admin2', true);
select tests.eq((select count(*)::int from platform_admins), 2, 'two admins');
select tests.logout();
insert into auth.users (id, email, raw_app_meta_data) values ('d0000000-0000-0000-0000-000000000009', 'device-9@devices.mcfly.invalid', '{"kind": "device"}');
select tests.login(:'admin');
select tests.throws($$select admin_set_admin('d0000000-0000-0000-0000-000000000009', true)$$, 'a display account can''t be an admin', 'no display admins');
select admin_set_admin(:'admin', false);
select tests.throws($$select admin_overview()$$, 'admin only', 'the removed admin is out');
select tests.login(:'admin2');
select tests.eq((select count(*)::int from platform_admins), 1, 'one admin again');
select tests.eq((select admin_email from admin_list_audit(1, 0)), 'admin@example.com', 'audit names the acting admin');
select tests.ok((select count(*) from admin_list_audit()) >= 12, 'every change left a row');

-- ───────────────────────────── Overview ─────────────────────────────
select tests.eq((admin_overview()->>'agents')::int, 7, 'live agents counted');
select tests.eq((admin_overview()->>'devices')::int, 0, 'no displays left');
select tests.eq((admin_overview()->>'news_reports')::int, 0, 'no reports left');
