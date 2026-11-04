-- Messages (20261103000010): the people at home write from a display, the
-- person writes back from the app or the console, and a display's message
-- goes to the person's phones as a notification.
\set ON_ERROR_STOP 1
\set device  'd0000000-0000-0000-0000-000000000001'
\set device2 'd0000000-0000-0000-0000-000000000002'
\set admin   'ad000000-0000-0000-0000-000000000001'
\set other   'ad000000-0000-0000-0000-000000000002'
\set kitchen '00000000-0000-0000-0000-00000000d001'
\set token   'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90'
insert into auth.users (id, email, raw_app_meta_data) values
  (:'admin', 'admin@example.com', '{}'),
  (:'device', 'device-1@devices.mcfly.invalid', '{"kind": "device"}'),
  (:'device2', 'device-2@devices.mcfly.invalid', '{"kind": "device"}'),
  (:'other', 'someone@example.com', '{}');
insert into devices (id, user_id, name) values (:'kitchen', :'device', 'Kitchen'),
                                               ('00000000-0000-0000-0000-00000000d002', :'device2', 'Den');

-- Who may call what.
select tests.ok(not has_function_privilege('anon', 'send_message(text, text, text)', 'execute'), 'anon cannot send');
select tests.ok(has_function_privilege('authenticated', 'send_message(text, text, text)', 'execute'), 'a signed-in caller may try');
select tests.ok(has_function_privilege('authenticated', 'read_messages(uuid)', 'execute'), 'and read');
select tests.ok(has_function_privilege('authenticated', 'register_push_token(text, text, text, text)', 'execute'), 'and register a phone');
select tests.ok(not has_function_privilege('authenticated', 'message_push(uuid)', 'execute'), 'message_push is service only');
select tests.ok(not has_function_privilege('authenticated', 'message_notified(uuid, text)', 'execute'), 'message_notified is service only');
select tests.ok(not has_function_privilege('authenticated', 'push_token_gone(text)', 'execute'), 'push_token_gone is service only');
select tests.ok(not has_function_privilege('authenticated', 'messages_notify()', 'execute'), 'the trigger function is no one''s to call');

-- ───────────────────────────── A display sends ─────────────────────────────
select tests.login(:'device');
select send_message(E'  I''m home!\r\n\r\n\r\n\r\nCan I have a snack?\t:)  ') as m \gset
select tests.eq((:'m'::jsonb)->>'sender_kind', 'display', 'a display''s message');
select tests.eq((:'m'::jsonb)->>'sender_name', 'Kitchen', 'no names listed: it is the display''s');
select tests.eq((:'m'::jsonb)->>'body', E'I''m home!\n\nCan I have a snack? :)', 'trimmed, \r\n made \n, blank lines made one, tabs spaces');
select tests.eq((:'m'::jsonb)->>'via', 'display', 'via the display');
select tests.eq(((:'m'::jsonb)->>'device_id')::uuid, :'kitchen'::uuid, 'from this display');
select tests.eq(((:'m'::jsonb)->>'author')::uuid, :'device'::uuid, 'by its device user');
select tests.eq((:'m'::jsonb)->>'read_at', null, 'unread');
-- A name with none listed: still the display's.
select tests.eq(send_message('hello', 'Mia')->>'sender_name', 'Kitchen', 'a name nobody listed is not taken');

select tests.throws($$select send_message('   ')$$, 'write something to send', 'blank');
select tests.throws($$select send_message(null)$$, 'write something to send', 'null');
select tests.throws($$select send_message(repeat('a', 501))$$, 'a message can be at most 500 characters', 'too long');
select tests.ok(length(send_message(repeat('a', 500))->>'body') = 500, '500 characters go');
select tests.throws($$select send_message(E'hi\u0007there')$$, 'a message can''t hold control characters', 'a bell');
select tests.throws($$insert into messages (sender_kind, sender_name, body, via) values ('person', 'Dad', 'x', 'app')$$,
                    'new row violates row-level security policy%', 'a display cannot write a row itself');
select tests.eq(tests.affected($$update messages set read_at = now()$$), 0, 'or mark one read by hand');

-- ───────────────────────────── Names ─────────────────────────────
select tests.login(:'admin');
select tests.eq(admin_set_message_names(array['  Mia ', '', 'Leo', null, 'Sam']), array['Mia', 'Leo', 'Sam'], 'trimmed, blanks out');
select tests.eq((select message_names from platform_settings), array['Mia', 'Leo', 'Sam'], 'kept in the settings');
select tests.eq((select action from admin_audit_log order by created_at desc, id desc limit 1), 'set_message_names', 'audited');
select tests.throws($$select admin_set_message_names(array['Mia', 'mia'])$$, 'mia is there twice', 'the same name twice');
select tests.throws($$select admin_set_message_names(array['a','b','c','d','e','f','g','h','i'])$$, 'at most 8 names', 'nine names');
select tests.throws($$select admin_set_message_names(array[repeat('x', 25)])$$, 'each name must be 1 to 24 characters', 'a long name');
select tests.throws($$select admin_set_message_names(array[E'Mia\nLeo'])$$, 'each name must be one line', 'two lines');
select tests.login(:'other');
select tests.throws($$select admin_set_message_names(array['Mia'])$$, 'admin only', 'not an admin');
select tests.login(:'device');
select tests.throws($$select admin_set_message_names(array['Mia'])$$, 'admin only', 'not a display');
select tests.eq((select message_names from platform_settings), array['Mia', 'Leo', 'Sam'], 'a display reads the names');

select tests.eq(send_message('Can we get pizza?', ' mia ')->>'sender_name', 'Mia', 'a listed name, any case: the list''s spelling');
select tests.eq(send_message('Me too', 'LEO')->>'sender_name', 'Leo', 'another');
select tests.eq(send_message('From the kitchen')->>'sender_name', 'Kitchen', 'nobody picked: the display');
select tests.throws($$select send_message('hi', 'Zed')$$, 'pick who is writing: Mia, Leo, Sam', 'somebody not listed');

-- ───────────────────────────── The person replies ─────────────────────────────
select tests.login(:'admin');
select send_message('Yes, pizza tonight') as r \gset
select tests.eq((:'r'::jsonb)->>'sender_kind', 'person', 'the person''s');
select tests.eq((:'r'::jsonb)->>'sender_name', 'Parent', 'no name yet: Parent');
select tests.eq((:'r'::jsonb)->>'via', 'app', 'via the app by default');
select tests.eq((:'r'::jsonb)->>'device_id', null, 'from no display');
select tests.eq(set_message_name('  Dad '), 'Dad', 'named');
select tests.eq((select message_name from profiles where id = :'admin'), 'Dad', 'on their profile');
select tests.eq(send_message('Love you', null, 'console')->>'sender_name', 'Dad', 'the reply carries it');
select tests.eq((select via from messages where body = 'Love you'), 'console', 'via the console');
select tests.eq(send_message('From the app', 'Somebody else')->>'sender_name', 'Dad', 'the person can''t send as anyone else');
select tests.throws($$select set_message_name(repeat('x', 25))$$, 'your name must be 1 to 24 characters', 'a long name');
select tests.throws($$update profiles set message_name = repeat('x', 30) where id = 'ad000000-0000-0000-0000-000000000001'$$,
                    '%message_name_check%', 'not even directly');
select tests.eq(set_message_name(''), null, 'blank clears it');
select set_message_name('Dad');

select tests.login(:'other');
select tests.throws($$select send_message('hi')$$, 'only a paired display or an admin can send a message', 'someone else');
select tests.throws($$select set_message_name('Me')$$, 'only the person can name themselves', 'naming needs an admin');
select tests.eq((select count(*)::int from messages), 0, 'and reads nothing');
select tests.login(null);
select tests.throws($$select send_message('hi')$$, 'permission denied%', 'anon');
select tests.login_service();
select tests.throws($$select send_message('hi')$$, 'only a paired display or an admin can send a message', 'not the service role either');

-- ───────────────────────────── Reading ─────────────────────────────
select tests.login(:'device');
select tests.ok((select count(*) from messages) >= 9, 'a display reads the thread');
select tests.eq((select count(*)::int from messages where sender_kind = 'person' and read_at is null), 3, 'three replies unread');
select tests.eq(read_messages(((:'r'::jsonb)->>'id')::uuid), 1, 'up to the first reply: one');
select tests.eq((select read_at is not null from messages where id = ((:'r'::jsonb)->>'id')::uuid), true, 'it is read');
select tests.eq(read_messages(), 2, 'the rest');
select tests.eq(read_messages(), 0, 'nothing left');
select tests.eq((select count(*)::int from messages where sender_kind = 'display' and read_at is not null), 0, 'a display never reads its own side');
select tests.throws($$select read_messages('00000000-0000-0000-0000-000000000000')$$, 'message not found', 'an unknown id');

select tests.login(:'admin');
select tests.eq((select count(*)::int from messages where sender_kind = 'display' and read_at is null), 6, 'six from home unread');
select tests.eq(read_messages(), 6, 'the person reads them');
select tests.login(:'other');
select tests.throws($$select read_messages()$$, 'only a paired display or an admin can read messages', 'someone else');

-- The second display sees the same thread and sends as itself.
select tests.login(:'device2');
select tests.eq(send_message('From the den')->>'sender_name', 'Den', 'another display, nobody picked: its name');
select tests.ok((select count(*) from messages where sender_name = 'Kitchen') > 0, 'one household thread');

-- ───────────────────────────── Too many ─────────────────────────────
select tests.logout();
delete from messages where device_id = :'kitchen';
select tests.login(:'device');
select send_message('spam ' || g) from generate_series(1, 10) g;
select tests.throws($$select send_message('eleven')$$, 'slow down: wait a minute before sending another message', 'ten a minute');
select tests.login(:'device2');
select tests.eq(send_message('Not me')->>'sender_name', 'Den', 'the limit is per display');
select tests.logout();
update messages set created_at = now() - interval '2 minutes' where device_id = :'kitchen';
insert into messages (sender_kind, sender_name, body, device_id, via, created_at)
select 'display', 'Kitchen', 'old ' || g, :'kitchen', 'display', now() - interval '10 minutes' from generate_series(1, 50) g;
select tests.login(:'device');
select tests.throws($$select send_message('sixty-one')$$, 'that''s a lot of messages: wait a while before sending more', 'sixty an hour');
select tests.logout();
update messages set created_at = now() - interval '2 hours' where device_id = :'kitchen';
select tests.login(:'device');
select tests.eq(send_message('Back again')->>'body', 'Back again', 'an hour on, it goes');

-- ───────────────────────────── Phones ─────────────────────────────
select tests.login(:'admin');
select register_push_token(upper(:'token'), 'production', 'com.bot.mcfly', 'ios');
select tests.eq((select count(*)::int from push_tokens), 0, 'tokens are invisible, even to the admin');
select tests.throws($$select register_push_token('nope', 'production', 'com.bot.mcfly')$$, 'that isn''t a device token', 'a bad token');
select tests.throws($$select register_push_token(repeat('ab', 32), 'staging', 'com.bot.mcfly')$$, 'environment must be sandbox or production', 'a bad environment');
select tests.throws($$select register_push_token(repeat('ab', 32), 'sandbox', 'com bot')$$, 'that isn''t a bundle id', 'a bad bundle id');
select tests.throws($$select register_push_token(repeat('ab', 32), 'sandbox', 'com.bot.mcfly', 'android')$$, 'platform must be ios or macos', 'a bad platform');
select register_push_token(repeat('cd', 32), 'sandbox', 'com.bot.mcfly.dev');
select tests.login(:'device');
select tests.throws($$select register_push_token(repeat('ef', 32), 'sandbox', 'com.bot.mcfly')$$, 'only the person gets notifications', 'not a display');
select tests.login(:'other');
select tests.throws($$select register_push_token(repeat('ef', 32), 'sandbox', 'com.bot.mcfly')$$, 'only the person gets notifications', 'not someone else');
select tests.login_service();
select tests.throws($$select register_push_token(repeat('ef', 32), 'sandbox', 'com.bot.mcfly')$$, 'only the person gets notifications', 'not the service role');
select tests.eq((select token from push_tokens where environment = 'production'), :'token', 'kept lower-case');
select tests.eq((select platform from push_tokens where environment = 'sandbox'), 'ios', 'ios by default');

-- What notify reads.
select tests.logout();
select id as latest from messages where body = 'Back again' \gset
select tests.login(:'admin');
select tests.throws($$select message_push('00000000-0000-0000-0000-000000000000')$$, 'permission denied%', 'not from a sign-in');
select tests.login_service();
select message_push(:'latest') as p \gset
select tests.eq((:'p'::jsonb)->>'sender_name', 'Kitchen', 'who');
select tests.eq((:'p'::jsonb)->>'body', 'Back again', 'what');
select tests.eq((:'p'::jsonb)->>'device_name', 'Kitchen', 'where');
select tests.eq(((:'p'::jsonb)->>'displays')::int, 2, 'how many displays');
select tests.eq(jsonb_array_length((:'p'::jsonb)->'tokens'), 2, 'every phone of the admin');
select tests.eq(((:'p'::jsonb)->>'unread')::int, (select count(*)::int from messages where sender_kind = 'display' and read_at is null), 'the badge: unread from home');
select tests.eq(message_push((select id from messages where sender_kind = 'person' limit 1)), null::jsonb, 'nothing for the person''s own');
select tests.eq(message_push('00000000-0000-0000-0000-000000000000'), null::jsonb, 'nothing for one that''s gone');

select message_notified(:'latest', 'no phone took it');
select tests.eq((select notify_error from messages where id = :'latest'), 'no phone took it', 'why it didn''t go');
select message_notified(:'latest');
select tests.ok((select notified_at is not null and notify_error is null from messages where id = :'latest'), 'it went');
select message_notified(:'latest', 'a later failure');
select tests.ok((select notified_at is not null and notify_error is null from messages where id = :'latest'), 'once it went, it went');

select push_token_gone(:'token');
select tests.eq((select count(*)::int from push_tokens), 1, 'a dead token goes');

-- Another admin signs in on the same phone: the token moves to them.
select tests.logout();
insert into platform_admins (user_id) values (:'other');
select tests.login(:'other');
select register_push_token(repeat('cd', 32), 'sandbox', 'com.bot.mcfly.dev');
select tests.logout();
select tests.eq((select user_id from push_tokens), :'other'::uuid, 'moved');
select tests.login(:'admin');
select tests.eq(unregister_push_token(repeat('cd', 32)), false, 'not theirs to drop now');
select tests.login(:'other');
select tests.eq(unregister_push_token(upper(repeat('cd', 32))), true, 'signing out drops it');
select tests.logout();
select tests.eq((select count(*)::int from push_tokens), 0, 'none left');
delete from platform_admins where user_id = :'other';

-- ───────────────────────────── Housekeeping ─────────────────────────────
-- No Vault or pg_net here: the trigger lets the message in and sends nothing.
select tests.ok((select count(*) from messages where body = 'Back again') = 1, 'the trigger never blocks a message');
update messages set created_at = now() - interval '366 days' where body = 'Yes, pizza tonight';
select tests.login(:'admin');
select send_message('A new day');
select tests.eq((select count(*)::int from messages where body = 'Yes, pizza tonight'), 0, 'a year on, a message goes');
select tests.logout();
delete from devices where id = :'kitchen';
select tests.ok((select count(*) from messages where sender_name = 'Kitchen' and device_id is null) > 0, 'a revoked display leaves its messages');

-- ───────────────────────────── Away mode (20261104000010) ─────────────────────────────
select tests.ok(not has_function_privilege('anon', 'set_away(boolean, timestamptz, text)', 'execute'), 'anon cannot set away');
insert into devices (id, user_id, name) values ('00000000-0000-0000-0000-00000000d009', 'd0000000-0000-0000-0000-000000000001', 'Kitchen again')
  on conflict do nothing;
select tests.login(:'admin');
select set_away(true, null, '  At work  ') as a \gset
select tests.eq((:'a'::jsonb)->>'away', 'true', 'away');
select tests.eq((:'a'::jsonb)->>'note', 'At work', 'the note, trimmed');
select tests.eq((:'a'::jsonb)->>'name', 'Dad', 'under the name the household uses');
select tests.eq((:'a'::jsonb)->>'until', null, 'until it''s turned off');
select tests.eq((select action from admin_audit_log order by created_at desc, id desc limit 1), 'set_away', 'audited');
select away_since as first_since from platform_settings \gset
select set_away(true, now() + interval '3 hours', '');
select tests.eq((select away_since from platform_settings), :'first_since'::timestamptz, 'on again keeps when it began');
select tests.ok((select away_until > now() + interval '2 hours' from platform_settings), 'now until a time');
select tests.eq((select away_note from platform_settings), null, 'a blank note clears it');
select tests.throws($$select set_away(true, now() - interval '1 minute')$$, 'pick a time that hasn''t passed', 'a time gone by');
select tests.throws($$select set_away(true, now() + interval '15 days')$$, 'away for at most two weeks at a time', 'too far out');
select tests.throws($$select set_away(true, null, repeat('x', 81))$$, 'the note can be at most 80 characters', 'a long note');
select tests.throws($$select set_away(true, null, E'two\nlines')$$, 'the note must be one line', 'two lines');
select tests.throws($$select set_away(null)$$, 'say whether you''re away', 'neither');
-- A display reads it, as it reads the names.
select tests.login(:'device2');
select tests.ok((select away_since is not null and away_name = 'Dad' from platform_settings), 'a display sees it');
select tests.throws($$select set_away(false)$$, 'only the person can say they''re away', 'but can''t change it');
select tests.login(:'other');
select tests.throws($$select set_away(false)$$, 'only the person can say they''re away', 'nor can someone else');
select tests.login_service();
select tests.throws($$select set_away(false)$$, 'only the person can say they''re away', 'nor the service role');
select tests.login(:'admin');
select tests.eq(set_away(false)->>'away', 'false', 'home again');
select tests.ok((select away_since is null and away_until is null and away_note is null and away_name is null from platform_settings), 'all of it cleared');
-- Run out on its own: still in the row, but past away_until; on again starts afresh.
select tests.logout();
update platform_settings set away_since = now() - interval '5 hours', away_until = now() - interval '1 hour', away_name = 'Dad';
select tests.login(:'admin');
select set_away(true);
select tests.ok((select away_since > now() - interval '1 minute' from platform_settings), 'run out: a new start');
select set_away(false);
