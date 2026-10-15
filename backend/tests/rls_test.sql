-- Who sees what: a paired display reads the feeds and nothing else, an
-- admin reads everything, a signed-in stranger and anon see nothing.
\set ON_ERROR_STOP 1
\set device   'd0000000-0000-0000-0000-000000000001'
\set device2  'd0000000-0000-0000-0000-000000000002'
\set stranger 'e0000000-0000-0000-0000-000000000001'
\set admin    'ad000000-0000-0000-0000-000000000001'

-- The first person to sign up is the admin (accounts_test); the rest are not.
insert into auth.users (id, email, raw_app_meta_data) values
  (:'admin', 'admin@example.com', '{}'),
  (:'device', 'device-1@devices.mcfly.invalid', '{"kind": "device"}'),
  (:'device2', 'device-2@devices.mcfly.invalid', '{"kind": "device"}'),
  (:'stranger', 'stranger@example.com', '{}');
insert into devices (id, user_id, name) values
  ('00000000-0000-0000-0000-00000000d001', :'device', 'Kitchen'),
  ('00000000-0000-0000-0000-00000000d002', :'device2', 'Office');

-- ───────────────────────────── Anon ─────────────────────────────
select tests.login(null);
select tests.ok(not can_read(), 'anon cannot read');
select tests.eq((select count(*)::int from agents), 0, 'anon sees no agents');
select tests.eq((select count(*)::int from briefs), 0, 'anon sees no briefs');
select tests.eq((select count(*)::int from quotes_latest), 0, 'anon sees no quotes');
select tests.eq((select count(*)::int from news_items), 0, 'anon sees no news');
select tests.eq((select count(*)::int from platform_settings), 0, 'anon sees no settings');
select tests.eq((select count(*)::int from devices), 0, 'anon sees no devices');
select tests.eq((select count(*)::int from agent_keys), 0, 'anon sees no keys');
select tests.throws($$select admin_overview()$$, 'permission denied%', 'anon cannot call admin RPCs');

-- ──────────────────────────── Stranger ────────────────────────────
select tests.login(:'stranger');
select tests.ok(not can_read(), 'a signed-in stranger cannot read');
select tests.eq((select count(*)::int from agents), 0, 'stranger sees no agents');
select tests.eq((select count(*)::int from briefs), 0, 'stranger sees no briefs');
select tests.eq((select count(*)::int from quotes), 0, 'stranger sees no quotes');
select tests.eq((select count(*)::int from symbols), 0, 'stranger sees no symbols');
select tests.eq((select count(*)::int from news_reports), 0, 'stranger sees no reports');
select tests.eq((select count(*)::int from platform_settings), 0, 'stranger sees no settings');
select tests.eq((select count(*)::int from devices), 0, 'stranger sees no devices');
select tests.eq((select count(*)::int from agent_keys), 0, 'stranger sees no keys');
select tests.eq((select count(*)::int from ingest_log), 0, 'stranger sees no log');
select tests.throws($$select admin_overview()$$, 'admin only', 'stranger cannot call admin RPCs');

-- ───────────────────────────── Display ─────────────────────────────
select tests.login(:'device');
select tests.ok(is_device(), 'device is a device');
select tests.ok(can_read(), 'device can read');
select tests.eq((select count(*)::int from agents), 6, 'device reads agents');
select tests.eq((select count(*)::int from briefs), 2, 'device reads briefs');
select tests.eq((select count(*)::int from quotes_latest), 4, 'device reads the latest quotes');
select tests.eq((select count(*)::int from quotes), 6, 'device reads quote history');
select tests.eq((select count(*)::int from symbols), 4, 'device reads symbols');
select tests.eq((select count(*)::int from news_reports), 1, 'device reads reports');
select tests.eq((select count(*)::int from news_items), 6, 'device reads news items');
select tests.eq((select display_name from platform_settings), 'McFly', 'device reads settings');
select tests.eq((select count(*)::int from devices), 1, 'device sees only itself');
select tests.eq((select count(*)::int from agent_keys), 0, 'device never sees keys');
select tests.eq((select count(*)::int from ingest_log), 0, 'device sees no ingest log');
select tests.eq((select count(*)::int from admin_audit_log), 0, 'device sees no audit log');
select tests.eq((select count(*)::int from platform_admins), 0, 'device sees no admins');
select tests.eq((select count(*)::int from pairing_codes), 0, 'device sees no pairing codes');

-- Writes: only its own check-in time.
select tests.eq(tests.affected($$update devices set last_seen_at = now() where id = '00000000-0000-0000-0000-00000000d001'$$), 1, 'device checks in');
select tests.eq(tests.affected($$update devices set last_seen_at = now() where id = '00000000-0000-0000-0000-00000000d002'$$), 0, 'device cannot touch another display');
select tests.throws($$update devices set name = 'Hacked' where id = '00000000-0000-0000-0000-00000000d001'$$,
                    'a display can only update its check-in time', 'device cannot rename itself');
select tests.throws($$insert into briefs (agent_id, title) values ('00000000-0000-0000-0000-00000000a001', 'forged')$$,
                    '%row-level security%', 'device cannot write briefs');
select tests.throws($$insert into quotes (agent_id, symbol, price) values ('00000000-0000-0000-0000-00000000a001', 'X', 1)$$,
                    '%row-level security%', 'device cannot write quotes');
select tests.eq(tests.affected($$delete from news_reports$$), 0, 'device cannot delete reports');
select tests.eq(tests.affected($$update platform_settings set display_name = 'x'$$), 0, 'device cannot change settings');
select tests.throws($$select admin_overview()$$, 'admin only', 'device cannot call admin RPCs');
select tests.throws($$select ingest_briefs('00000000-0000-0000-0000-00000000a001', '[]')$$, 'permission denied%', 'device cannot call ingest');
select tests.throws($$select agent_for_key('x')$$, 'permission denied%', 'device cannot look up keys');

-- ───────────────────────────── Admin ─────────────────────────────
select tests.login(:'admin');
select tests.ok(is_platform_admin(), 'admin is an admin');
select tests.ok(can_read(), 'admin can read');
select tests.eq((select count(*)::int from devices), 2, 'admin sees every display');
select tests.eq((select count(*)::int from ingest_log), 3, 'admin reads the ingest log');
select tests.eq((select count(*)::int from platform_admins), 1, 'admin reads admins');
select tests.eq((select count(*)::int from agent_keys), 0, 'even admins read keys only through the service role');
select tests.ok((admin_overview()->>'devices')::int = 2, 'admin overview counts displays');

-- ───────────────────────── Service role ─────────────────────────
select tests.login_service();
select tests.ok(is_platform_admin(), 'service role counts as admin');
select tests.eq((select count(*)::int from agent_keys), 6, 'service role reads keys');
select tests.eq((select name from agent_for_key(key_hash('mcf_0000000000000000000000000000000000grok0'))), 'Grok', 'key lookup finds Grok');
select tests.eq((select count(*)::int from agent_for_key(key_hash('mcf_wrong'))), 0, 'unknown key finds nobody');
