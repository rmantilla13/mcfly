-- Per-display settings: checked keys and ranges; the admin edits any
-- display's, a display only its own and only through the function.
\set ON_ERROR_STOP 1
\set device   'd0000000-0000-0000-0000-000000000001'
\set device2  'd0000000-0000-0000-0000-000000000002'
\set stranger 'e0000000-0000-0000-0000-000000000001'
\set admin    'ad000000-0000-0000-0000-000000000001'
\set kitchen  '00000000-0000-0000-0000-00000000d001'
\set office   '00000000-0000-0000-0000-00000000d002'

insert into auth.users (id, email, raw_app_meta_data) values
  (:'admin', 'admin@example.com', '{}'),
  (:'device', 'device-1@devices.mcfly.invalid', '{"kind": "device"}'),
  (:'device2', 'device-2@devices.mcfly.invalid', '{"kind": "device"}'),
  (:'stranger', 'stranger@example.com', '{}');
insert into devices (id, user_id, name) values (:'kitchen', :'device', 'Kitchen'), (:'office', :'device2', 'Office');

select tests.ok(not has_function_privilege('authenticated', 'clean_device_settings(jsonb)', 'execute'), 'the checker is internal');

-- A display: its own row, through the function only.
select tests.login(:'device');
select tests.eq(device_update_settings('{"screensaver": "clock", "darkMode": true, "unknownThing": 5}'),
                '{"screensaver": "clock", "darkMode": true}'::jsonb, 'own settings saved, unknown keys dropped');
select tests.eq(device_update_settings('{"idleSeconds": 300}') ->> 'screensaver', 'clock', 'patches merge');
select tests.throws($$select device_update_settings('{"screensaver": "disco"}')$$, 'screensaver must be%', 'bad value');
select tests.throws($$select device_update_settings('{"idleSeconds": 5}')$$, 'idleSeconds is out of range', 'out of range');
select tests.throws($$select device_update_settings('{"darkMode": "yes"}')$$, 'darkMode must be true or false', 'wrong type');
select tests.throws($$select device_update_settings('{"bedtime": 22.5}')$$, 'bedtime is out of range', 'whole minutes only');
select tests.throws($$update devices set settings = '{"screensaver": "disco"}' where user_id = auth.uid()$$,
                    'a display changes its settings through device_update_settings', 'no direct writes');
select tests.eq(tests.affected(format('update devices set last_seen_at = now() where id = %L', :'kitchen')), 1, 'check-in still works');
-- The voice service's own wake word, as a display reports it (20261015000008).
select tests.eq(device_update_settings('{"wakewordModel": "hey_mcfly"}') ->> 'wakewordModel', 'hey_mcfly', 'a display runs Hey McFly');
-- The savers' backdrop (20261016000001).
select tests.eq(device_update_settings('{"backdrop": "dawn"}') ->> 'backdrop', 'dawn', 'a sky for the savers');
select tests.throws($$select device_update_settings('{"backdrop": "disco"}')$$, 'backdrop must be%', 'unknown backdrop');
select tests.eq((select settings from devices where id = :'office'), null::jsonb, 'cannot see another display');

select tests.login(:'stranger');
select tests.throws($$select device_update_settings('{"darkMode": true}')$$, 'not a paired display', 'not a display');
select tests.throws(format('select admin_update_device_settings(%L, ''{}'')', :'kitchen'), 'admin only', 'stranger cannot edit');

-- The admin: any display, listed with its settings.
select tests.login(:'admin');
select admin_update_device_settings(:'office', '{"wakewordModel": "alexa", "voiceSpeed": 1.25, "assistantProvider": "grok"}');
select tests.eq(admin_update_device_settings(:'office', '{"voice": "am_fenrir"}') ->> 'voice', 'am_fenrir', 'a Homestead voice');
select tests.throws(format('select admin_update_device_settings(%L, ''{"voice": "robot"}'')', :'office'), 'voice must be%', 'unknown voice');
select tests.eq((select settings ->> 'wakewordModel' from admin_list_devices() where id = :'office'), 'alexa', 'admin edit listed');
select tests.eq((select settings ->> 'screensaver' from admin_list_devices() where id = :'kitchen'), 'clock', 'the display''s own edit listed');
select tests.throws(format('select admin_update_device_settings(%L, ''{"voiceSpeed": 3}'')', :'office'), 'voiceSpeed must be%', 'checked for admins too');
select tests.throws($$select admin_update_device_settings('99999999-9999-9999-9999-999999999999', '{}')$$, 'display not found', 'unknown display');
select tests.eq((select details from admin_audit_log where action = 'update_device_settings' order by id limit 1),
                '{"wakewordModel": "alexa", "voiceSpeed": 1.25, "assistantProvider": "grok"}'::jsonb, 'audited');
select tests.eq(admin_update_device_settings(:'office', '{"wakewordModel": "hey_mcfly"}') ->> 'wakewordModel', 'hey_mcfly', 'the admin picks Hey McFly');
select tests.throws(format('select admin_update_device_settings(%L, ''{"wakewordModel": "hey_toaster"}'')', :'office'),
                    'wakewordModel must be hey_mcfly, %', 'unknown wake word');

select 'device_settings_test passed';
