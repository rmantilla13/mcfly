-- Calendar subscriptions: admin only, the link never leaves the server, and
-- the sync writes through ingest_events under the built-in agent.
\set ON_ERROR_STOP 1
\set device   'd0000000-0000-0000-0000-000000000001'
\set stranger 'e0000000-0000-0000-0000-000000000001'
\set admin    'ad000000-0000-0000-0000-000000000001'

insert into auth.users (id, email, raw_app_meta_data) values
  (:'admin', 'admin@example.com', '{}'),
  (:'device', 'device-1@devices.mcfly.invalid', '{"kind": "device"}'),
  (:'stranger', 'stranger@example.com', '{}');
insert into devices (id, user_id, name) values ('00000000-0000-0000-0000-00000000d001', :'device', 'Kitchen');

select tests.ok(not has_function_privilege('authenticated', 'calendar_sources_due(uuid)', 'execute'), 'due list is service only');
select tests.ok(not has_function_privilege('authenticated', 'calendar_source_synced(uuid, integer, text)', 'execute'), 'sync result is service only');
select tests.ok(not has_function_privilege('anon', 'list_calendar_sources()', 'execute'), 'anon cannot list');

select tests.login(:'stranger');
select tests.throws($$select admin_add_calendar_source('Work', 'https://calendar.google.com/x.ics')$$, 'admin only', 'stranger cannot add');
select tests.eq((select count(*)::int from list_calendar_sources()), 0, 'stranger sees none');

select tests.login(:'admin');
select admin_add_calendar_source('  Work ', 'webcal://calendar.google.com/calendar/ical/secret/basic.ics', '#4F7CF7') as work \gset
select tests.eq((select host from admin_list_calendar_sources()), 'calendar.google.com', 'console sees the host only');
select tests.ok(not exists (select 1 from admin_list_calendar_sources() t where t::text like '%secret%'), 'never the link');
select tests.ok(not exists (select 1 from admin_audit_log where details::text like '%secret%'), 'link not in the audit log');
select tests.throws('select * from calendar_sources', 'permission denied%', 'the table itself is closed to admins too');
select tests.throws($$select admin_add_calendar_source('Work', 'https://x.example/y.ics')$$, 'there is already a calendar called Work', 'names unique');
select tests.throws($$select admin_add_calendar_source('Bad', 'ftp://x')$$, 'paste the calendar''s iCal link%', 'bad link');
select tests.ok(exists (select 1 from agents where slug = 'calendar-subscriptions'), 'built-in agent made');

-- The sync, as the function does it.
select tests.login_service();
select tests.eq((select url from calendar_sources_due()), 'https://calendar.google.com/calendar/ical/secret/basic.ics', 'webcal became https');
select agent as cal_agent from calendar_sources_due() \gset
select ingest_events(:'cal_agent'::uuid, jsonb_build_array(
  jsonb_build_object('id', 'a', 'title', 'Standup', 'starts_at', now() + interval '1 hour', 'calendar', 'Work'),
  jsonb_build_object('id', 'b', 'title', 'Review', 'starts_at', now() + interval '2 hours', 'calendar', 'Work')), 'Work');
select calendar_source_synced(:'work', 2);
select tests.eq((select event_count from calendar_sources), 2, 'count recorded');
select calendar_source_synced(:'work', 0, 'the link answered 404');
select tests.eq((select row(event_count, last_error)::text from calendar_sources), row(2, 'the link answered 404')::text,
                'an error keeps the last good count');

select tests.login(:'device');
select tests.eq((select row(name, last_error)::text from list_calendar_sources()), row('Work', 'the link answered 404')::text,
                'a display sees name and health');

-- Rename carries the events; delete takes them.
select tests.login(:'admin');
select admin_update_calendar_source(:'work', name => 'Office', color => '#E2725B');
select tests.eq((select count(*)::int from events where calendar = 'Office'), 2, 'events renamed with it');
select tests.eq((select count(*)::int from events where calendar = 'Office' and color = '#E2725B'), 2, 'recolored');
select admin_update_calendar_source(:'work', enabled => false);
select tests.login_service();
select tests.eq((select count(*)::int from calendar_sources_due()), 0, 'paused ones are skipped');
select tests.login(:'admin');
select admin_delete_calendar_source(:'work');
select tests.eq((select count(*)::int from events where calendar = 'Office'), 0, 'its events went with it');
select tests.throws(format('select admin_delete_calendar_source(%L)', :'work'), 'calendar not found', 'twice');

-- Without pg_cron the schedule is skipped and the tick does nothing.
select tests.logout();
select calendar_sync_tick();

select 'calendar_test passed';
