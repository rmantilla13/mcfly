-- Grok bots: admin only; each is an agent without a key; claims are single;
-- runs finish into the schedule; the context follows the agent's scopes.
\set ON_ERROR_STOP 1
\set stranger 'e0000000-0000-0000-0000-000000000001'
\set admin    'ad000000-0000-0000-0000-000000000001'

insert into auth.users (id, email, raw_app_meta_data) values
  (:'admin', 'admin@example.com', '{}'),
  (:'stranger', 'stranger@example.com', '{}');

select tests.ok(not has_function_privilege('authenticated', 'bots_claim(integer, uuid)', 'execute'), 'claims are service only');
select tests.ok(not has_function_privilege('authenticated', 'bot_context(uuid)', 'execute'), 'context is service only');
select tests.login(:'stranger');
select tests.throws($$select admin_save_bot(name => 'X', prompt => 'Summarize the news for me.')$$, 'admin only', 'stranger cannot');

select tests.login(:'admin');
update platform_settings set timezone = 'America/Chicago';
select admin_save_bot(name => 'Morning brief', prompt => 'Write my morning briefing from the news.', every_minutes => 1440,
                      at_minute => 420, scopes => '{memory:read,calendar:read}') as bot \gset
select tests.eq((select row(name, output, every_minutes, at_minute, web_search, x_search, enabled)::text from admin_list_bots()),
                row('Morning brief', 'brief', 1440, 420, true, true, true)::text, 'saved with defaults');
select tests.eq((select scopes from admin_list_bots()), '{calendar:read,memory:read}'::text[], 'scopes on its agent');
select tests.login_service();
select tests.eq((select count(*)::int from agent_keys k join bots b on b.agent_id = k.agent_id), 0, 'a bot has no key');
-- Anchored at 7:00 Chicago: the next run is a 7:00 local.
select tests.eq((select to_char(next_run_at at time zone 'America/Chicago', 'HH24:MI') from bots), '07:00', 'next run at the anchor');
select tests.eq(to_char(bot_next_run(120, 420, '2026-10-15 13:30:00+00') at time zone 'America/Chicago', 'HH24:MI'), '09:00',
                'every 2 h from 7:00: 8:30 local -> 9:00');
select tests.eq(to_char(bot_next_run(120, 420, '2026-10-16 04:30:00+00') at time zone 'America/Chicago', 'YYYY-MM-DD HH24:MI'),
                '2026-10-16 07:00', 'after the last slot (23:00), tomorrow 7:00');
select tests.eq(bot_next_run(60, null, '2026-10-15 12:00:00+00'), '2026-10-15 13:00:00+00'::timestamptz, 'plain interval');

-- Not due yet: nothing claimed. Asked for by id ("Run now"): claimed once.
select tests.eq((select count(*)::int from bots_claim()), 0, 'nothing due');
select run_id as run from bots_claim(1, :'bot') \gset
select tests.eq((select count(*)::int from bots_claim(1, :'bot')), 0, 'a running bot is not claimed twice');
select tests.eq((select status from bot_runs where id = :run), 'running', 'run recorded');

-- Context follows the scopes.
select tests.logout();
insert into memories (agent_id, text) values (null, 'Lives in Austin.');
select tests.login_service();
select tests.eq((select bot_context(agent_id) -> 'memories' from bots), '["Lives in Austin."]'::jsonb, 'memory:read gives notes');
select tests.eq((select bot_context(agent_id) ->> 'timezone' from bots), 'America/Chicago', 'and the zone');

select bot_run_finished(:run, 'ok', 'Morning briefing', null, 4, 'grok-4.7');
select tests.eq((select row(last_status, last_error, running_since)::text from bots), row('ok', null, null)::text, 'finished');
select tests.ok((select next_run_at > now() from bots), 'scheduled again');
select tests.eq((select row(status, title, sources)::text from bot_runs where id = :run), row('ok', 'Morning briefing', 4)::text, 'run kept');

select tests.login(:'admin');
select tests.eq((select count(*)::int from admin_list_bot_runs(:'bot')), 1, 'runs listed');
select admin_save_bot(id => :'bot', enabled => false, scopes => '{}');
select tests.eq((select row(enabled, scopes)::text from admin_list_bots()), row(false, '{}'::text[])::text, 'paused, scopes removed');
select tests.login_service();
select tests.eq((select bot_context(agent_id) -> 'memories' from bots), '[]'::jsonb, 'no scope, no notes');
select tests.login(:'admin');
select tests.throws($$select admin_save_bot(name => 'X', prompt => 'short')$$, 'write what the bot should do%', 'prompt too short');
select admin_delete_bot(:'bot');
select tests.eq((select count(*)::int from admin_list_bots()), 0, 'deleted');
select tests.eq((select count(*)::int from agents where name = 'Morning brief'), 0, 'with its agent');

-- The backend status the console shows (no pg_cron or Vault here: nulls).
select tests.login(:'admin');
select tests.eq((select admin_backend_status() ->> 'bots'), '0', 'status counts bots');
select tests.ok((select admin_backend_status() ? 'latest_migration'), 'status has the migration key');

select 'bots_test passed';
