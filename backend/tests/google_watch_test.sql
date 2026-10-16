-- Google push notification channels (20261016000012): service role only,
-- one per Google calendar, renewed in place, gone with the calendar.
\set ON_ERROR_STOP 1
\set admin 'ad000000-0000-0000-0000-000000000001'

insert into auth.users (id, email, raw_app_meta_data) values (:'admin', 'admin@example.com', '{}');

select tests.ok(not has_function_privilege('authenticated', 'google_watch_list()', 'execute'), 'list is service only');
select tests.ok(not has_function_privilege('authenticated', 'google_watch_save(uuid, text, text, text, timestamptz)', 'execute'), 'save is service only');
select tests.ok(not has_function_privilege('authenticated', 'google_watch_failed(uuid, text)', 'execute'), 'failed is service only');
select tests.ok(not has_function_privilege('authenticated', 'google_watch_for_channel(text)', 'execute'), 'lookup is service only');

-- An account with one Google calendar, and a link.
select tests.login_service();
select google_account_save('ricky@example.com', 'refresh-token', 'scope', :'admin') as acct \gset
select tests.login(:'admin');
select admin_add_google_calendar(:'acct', 'ricky@example.com', 'Ricky', '#4F7CF7') as gcal \gset
select admin_add_calendar_source('Family', 'https://p12-caldav.icloud.com/published/2/abc', '#F07F5A') as link \gset
select tests.throws('select * from google_watch_channels', 'permission denied%', 'the table is closed to admins');
select tests.eq((select row(watch_expires_at, watch_error)::text from admin_list_calendar_sources() where id = :'gcal'), row(null::timestamptz, null::text)::text, 'not watched yet');

-- The channel Google made.
select tests.login_service();
select google_watch_save(:'gcal', 'channel-one', 'resource-abc', '0123456789abcdef0123456789abcdef', now() + interval '7 days');
select tests.throws(format('select google_watch_save(%L, %L, %L, %L, now())', :'link', 'channel-x', 'r', '0123456789abcdef0123456789abcdef'),
                    'not a Google calendar', 'links are not watched');
select tests.throws(format('select google_watch_save(%L, %L, %L, %L, now())', :'gcal', 'channel-two', 'r', 'short'),
                    '%violates check constraint%', 'the token must be long');
select tests.eq((select row(source_id, channel_id, resource_id)::text from google_watch_list()), row(:'gcal'::uuid, 'channel-one', 'resource-abc')::text, 'listed for renewal checks');
select tests.eq((select row(source_id, token, enabled)::text from google_watch_for_channel('channel-one')), row(:'gcal'::uuid, '0123456789abcdef0123456789abcdef', true)::text, 'a notification finds its calendar');
select tests.eq((select count(*)::int from google_watch_for_channel('channel-nope')), 0, 'an unknown channel finds nothing');

-- Renewal replaces the row in place; a refusal is shown, and cleared by the next channel.
select google_watch_save(:'gcal', 'channel-two', 'resource-abc', 'fedcba9876543210fedcba9876543210', now() + interval '7 days');
select tests.eq((select count(*)::int from google_watch_list()), 1, 'one channel per calendar');
select tests.eq((select channel_id from google_watch_list()), 'channel-two', 'the new one');
select tests.eq((select count(*)::int from google_watch_for_channel('channel-one')), 0, 'the old channel is forgotten');
select google_watch_failed(:'gcal', 'Google refused the notification channel (push.webhookUrlUnauthorized)');
select tests.login(:'admin');
select tests.eq((select watch_error from admin_list_calendar_sources() where id = :'gcal'), 'Google refused the notification channel (push.webhookUrlUnauthorized)', 'the refusal shows');
select tests.ok((select watch_expires_at > now() from admin_list_calendar_sources() where id = :'gcal'), 'and so does the expiry');
select tests.login_service();
select google_watch_save(:'gcal', 'channel-three', 'resource-abc', 'fedcba9876543210fedcba9876543210', now() + interval '7 days');
select tests.login(:'admin');
select tests.eq((select watch_error from admin_list_calendar_sources() where id = :'gcal'), null::text, 'a new channel clears it');

-- Pausing keeps the channel but the lookup says so; removing the calendar takes the channel.
select admin_update_calendar_source(:'gcal', enabled => false);
select tests.login_service();
select tests.eq((select enabled from google_watch_for_channel('channel-three')), false, 'a paused calendar is not read on a notification');
select tests.login(:'admin');
select admin_delete_calendar_source(:'gcal');
select tests.login_service();
select tests.eq((select count(*)::int from google_watch_list()), 0, 'the channel went with the calendar');

select 'google_watch_test passed';
