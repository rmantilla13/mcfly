-- Google Calendar by sign-in (20261016000011): the token never leaves the
-- server, picked calendars are ordinary subscriptions, and disconnecting an
-- account takes its calendars and their events with it.
\set ON_ERROR_STOP 1
\set device   'd0000000-0000-0000-0000-000000000001'
\set stranger 'e0000000-0000-0000-0000-000000000001'
\set admin    'ad000000-0000-0000-0000-000000000001'

insert into auth.users (id, email, raw_app_meta_data) values
  (:'admin', 'admin@example.com', '{}'),
  (:'device', 'device-1@devices.mcfly.invalid', '{"kind": "device"}'),
  (:'stranger', 'stranger@example.com', '{}');
insert into devices (id, user_id, name) values ('00000000-0000-0000-0000-00000000d001', :'device', 'Kitchen');

-- Only the functions touch the sign-in and the token.
select tests.ok(not has_function_privilege('authenticated', 'google_oauth_begin(text, uuid, text)', 'execute'), 'begin is service only');
select tests.ok(not has_function_privilege('authenticated', 'google_oauth_finish(text)', 'execute'), 'finish is service only');
select tests.ok(not has_function_privilege('authenticated', 'google_account_save(text, text, text, uuid)', 'execute'), 'save is service only');
select tests.ok(not has_function_privilege('authenticated', 'google_account_credentials(uuid)', 'execute'), 'credentials are service only');
select tests.ok(not has_function_privilege('authenticated', 'google_account_failed(uuid, text)', 'execute'), 'failed is service only');
select tests.ok(not has_function_privilege('authenticated', 'calendar_sources_due(uuid)', 'execute'), 'due list is service only');

-- The sign-in's state: one use, ten minutes.
select tests.login_service();
select google_oauth_begin('0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef', :'admin', 'https://mcfly.bot/calendars');
select tests.throws($$select google_oauth_begin('short', 'ad000000-0000-0000-0000-000000000001', 'https://mcfly.bot/calendars')$$,
                    '%violates check constraint%', 'a short state is refused');
select tests.throws($$select google_oauth_begin('fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210', 'ad000000-0000-0000-0000-000000000001', 'javascript:alert(1)')$$,
                    '%violates check constraint%', 'return_to must be a web address');
select tests.eq((select return_to from google_oauth_finish('0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef')),
                'https://mcfly.bot/calendars', 'finish gives the row back');
select tests.eq((select count(*)::int from google_oauth_finish('0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef')), 0, 'and only once');
select google_oauth_begin('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', :'admin', 'https://mcfly.bot/calendars');
update google_oauth_states set created_at = now() - interval '11 minutes';
select tests.eq((select count(*)::int from google_oauth_finish('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')), 0, 'an old state has expired');

-- Saving the sign-in.
select google_account_save(' Ricky@Example.com ', 'refresh-token-1', 'openid email https://www.googleapis.com/auth/calendar.readonly', :'admin') as acct \gset
select tests.eq((select email from google_accounts), 'ricky@example.com', 'email kept lower and trimmed');
select tests.throws($$select google_account_save('nope', 'tok', null, 'ad000000-0000-0000-0000-000000000001')$$, 'not an email address', 'an email is needed');
select tests.throws($$select google_account_save('a@b.c', '', null, 'ad000000-0000-0000-0000-000000000001')$$, 'no refresh token', 'a token is needed');
select tests.eq((select google_account_save('ricky@example.com', 'refresh-token-2', 'scope', :'admin')), :'acct'::uuid, 'connecting again keeps the row');
select tests.eq((select refresh_token from google_account_credentials(:'acct')), 'refresh-token-2', 'and takes the new token');
select tests.eq((select count(*)::int from admin_audit_log where action = 'connect_google_account' and admin_id = :'admin'), 2, 'the admin who began it is in the audit log');
select tests.ok(not exists (select 1 from admin_audit_log where details::text like '%refresh-token%'), 'token not in the audit log');

-- The console: sees the account, picks calendars, never the token.
select tests.login(:'stranger');
select tests.throws('select * from admin_list_google_accounts()', 'admin only', 'stranger cannot list accounts');
select tests.throws(format('select admin_add_google_calendar(%L, %L, %L)', :'acct', 'primary', 'Ricky'), 'admin only', 'stranger cannot add');

select tests.login(:'admin');
select tests.eq((select row(email, calendars)::text from admin_list_google_accounts()), row('ricky@example.com', 0)::text, 'admin sees the account');
select tests.throws('select * from google_accounts', 'permission denied%', 'the table itself is closed to admins');
select tests.throws(format('select * from google_account_credentials(%L)', :'acct'), 'permission denied%', 'and so is the token');
select admin_add_calendar_source('Work', 'https://calendar.google.com/calendar/ical/secret/basic.ics', '#4F7CF7') as link \gset
select admin_add_google_calendar(:'acct', 'ricky@example.com', 'Ricky', '#4F7CF7') as primary_cal \gset
select admin_add_google_calendar(:'acct', 'c_work123@group.calendar.google.com', 'Work', '#5B7CF5') as work_cal \gset
select tests.eq((select name from admin_list_calendar_sources() where id = :'work_cal'), 'Work (ricky@example.com)', 'a taken name gets the account appended');
select tests.eq((select row(kind, account_email, google_calendar_id, host)::text from admin_list_calendar_sources() where id = :'primary_cal'),
                row('google', 'ricky@example.com', 'ricky@example.com', 'calendar.google.com')::text, 'the list says whose calendar it is');
select tests.eq((select row(kind, account_email)::text from admin_list_calendar_sources() where id = :'link'), row('ical', null)::text, 'a link is still a link');
select tests.ok(not exists (select 1 from admin_list_calendar_sources() t where t::text like '%refresh-token%'), 'never the token');
select tests.throws(format('select admin_add_google_calendar(%L, %L, %L)', :'acct', 'ricky@example.com', 'Again'), 'that calendar is already added', 'a calendar is added once');
select tests.throws(format('select admin_add_google_calendar(%L, %L, %L)', '00000000-0000-0000-0000-000000000000', 'x', 'X'), 'that Google account isn''t connected', 'unknown account');
select tests.throws(format('select admin_add_google_calendar(%L, %L, %L)', :'acct', '', 'X'), 'which calendar?', 'a calendar id is needed');
select tests.eq((select calendars from admin_list_google_accounts()), 2, 'the account counts its calendars');

-- The sync list, as calendar-sync reads it.
select tests.login_service();
select tests.eq((select count(*)::int from calendar_sources_due()), 3, 'links and Google calendars are both due');
select tests.eq((select row(kind, google_calendar_id, account_email, refresh_token)::text from calendar_sources_due() where id = :'primary_cal'),
                row('google', 'ricky@example.com', 'ricky@example.com', 'refresh-token-2')::text, 'a Google calendar comes with its token');
select tests.eq((select row(kind, url)::text from calendar_sources_due() where id = :'link'),
                row('ical', 'https://calendar.google.com/calendar/ical/secret/basic.ics')::text, 'a link comes with its url');
select agent as cal_agent from calendar_sources_due() limit 1 \gset
select ingest_events(:'cal_agent'::uuid, jsonb_build_array(
  jsonb_build_object('id', 'g1', 'title', 'Standup', 'starts_at', now() + interval '1 hour'),
  jsonb_build_object('id', 'g2', 'title', 'Review', 'starts_at', now() + interval '2 hours')), 'Ricky');
select ingest_events(:'cal_agent'::uuid, jsonb_build_array(
  jsonb_build_object('id', 'w1', 'title', 'Planning', 'starts_at', now() + interval '3 hours')), 'Work (ricky@example.com)');
select calendar_source_synced(:'primary_cal', 2);
select google_account_failed(:'acct', 'Google no longer accepts this sign-in; connect the account again');
select tests.login(:'admin');
select tests.eq((select last_error from admin_list_google_accounts()), 'Google no longer accepts this sign-in; connect the account again', 'the account''s trouble shows');
select tests.login_service();
select google_account_failed(:'acct');
select tests.login(:'admin');
select tests.eq((select last_error from admin_list_google_accounts()), null::text, 'and clears');

-- Pause, rename and remove work as for a link.
select admin_update_calendar_source(:'primary_cal', name => 'Me', enabled => false);
select tests.eq((select count(*)::int from events where calendar = 'Me'), 2, 'rename carries the events');
select tests.login_service();
select tests.eq((select count(*)::int from calendar_sources_due() where id = :'primary_cal'), 0, 'paused ones are skipped');
select tests.login(:'admin');
select admin_delete_calendar_source(:'work_cal');
select tests.eq((select count(*)::int from events where calendar = 'Work (ricky@example.com)'), 0, 'its events went with it');
select tests.eq((select count(*)::int from events where calendar = 'Me'), 2, 'the other calendar''s stayed');

-- Disconnecting takes the account, its calendars and their events; the link stays.
select tests.login(:'stranger');
select tests.throws(format('select admin_delete_google_account(%L)', :'acct'), 'admin only', 'stranger cannot disconnect');
select tests.login(:'admin');
select tests.eq((select admin_delete_google_account(:'acct')), 'ricky@example.com', 'disconnect names the account');
select tests.eq((select count(*)::int from admin_list_google_accounts()), 0, 'account gone');
select tests.eq((select count(*)::int from admin_list_calendar_sources()), 1, 'its calendars went with it');
select tests.eq((select kind from admin_list_calendar_sources()), 'ical', 'the link stayed');
select tests.eq((select count(*)::int from events where calendar = 'Me'), 0, 'and so did their events');
select tests.eq((select count(*)::int from admin_audit_log where action = 'disconnect_google_account'), 1, 'audited');
select tests.throws(format('select admin_delete_google_account(%L)', :'acct'), 'that Google account isn''t connected', 'twice');

select 'google_calendar_test passed';
