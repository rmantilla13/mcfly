-- Dismissing a callout (20261021000070): who may, how long it lasts, and
-- what brings a blocked project's back.
\set ON_ERROR_STOP 1
\set gh     '00000000-0000-0000-0000-00000000a004'
\set device 'd0000000-0000-0000-0000-000000000001'
\set admin  'ad000000-0000-0000-0000-000000000001'
\set other  'ad000000-0000-0000-0000-000000000002'
insert into auth.users (id, email, raw_app_meta_data) values
  (:'admin', 'admin@example.com', '{}'),
  (:'device', 'device-1@devices.mcfly.invalid', '{"kind": "device"}'),
  (:'other', 'someone@example.com', '{}');
insert into devices (id, user_id, name) values ('00000000-0000-0000-0000-00000000d001', :'device', 'Kitchen');
select id as onyx from projects where key = 'onyx' \gset
-- An old one, run out yesterday: the next dismiss prunes it.
insert into dismissals (key, hide_until) values ('mover:old', now() - interval '1 day');

-- ───────────────────────────── A display dismisses ─────────────────────────────
select tests.login(:'device');
select dismiss('  Blocked:' || upper(:'onyx') || ' ') as d \gset
select tests.eq((:'d')::jsonb->>'key', 'blocked:' || :'onyx', 'the key, lower-cased and trimmed');
select tests.ok(((:'d')::jsonb->'hide_until') = 'null'::jsonb, 'a blocked project: until it changes');
select tests.eq((select count(*)::int from dismissals), 1, 'a display reads them; the run-out one is pruned');
select tests.eq((select device_id::text from dismissals), '00000000-0000-0000-0000-00000000d001', 'which display');
select tests.eq(tests.affected($$update dismissals set hide_until = now()$$), 0, 'a display cannot write them directly');
select tests.eq(tests.affected($$delete from dismissals$$), 0, 'nor delete them');
select tests.eq((select count(*)::int from dismissals where hide_until is not null), 0, 'unchanged');
-- Anything else: until the end of today in the account's zone (America/Chicago).
select (dismiss('metric:sales.today')->>'hide_until')::timestamptz as until \gset
select tests.eq(:'until'::timestamptz, (date_trunc('day', now() at time zone 'America/Chicago') + interval '1 day') at time zone 'America/Chicago',
                'until midnight where the account is');
select tests.throws($$select dismiss('  ')$$, 'say what to dismiss (an id of 1 to 300 characters)', 'nothing to dismiss');
select tests.throws($$select dismiss(repeat('x', 301))$$, 'say what to dismiss (an id of 1 to 300 characters)', 'too long');

-- ───────────────────────────── Nobody else ─────────────────────────────
select tests.login(:'other');
select tests.throws($$select dismiss('errors')$$, 'only a paired display or an admin can dismiss', 'a signed-in stranger');
select tests.eq((select count(*)::int from dismissals), 0, 'sees none');
select tests.login(null);
select tests.throws($$select dismiss('errors')$$, '%permission denied%', 'anon may not call it');
select tests.eq((select count(*)::int from dismissals), 0, 'anon sees none');

-- ───────────────────────────── Until the project changes ─────────────────────────────
select tests.login_service();
-- The agent sends the same project again (updated_at moves): still dismissed.
select ingest_projects(:'gh', '[{"key": "onyx", "name": "Onyx", "kind": "code", "status": "blocked", "progress": 80, "sort_order": 1,
  "summary": "Collections and the Mac app.", "next_step": "App Review answer on the FSKit entitlement"}]');
select tests.eq((select count(*)::int from dismissals where key = 'blocked:' || :'onyx'), 1, 'the same project again keeps it dismissed');
-- A new next step brings it back.
select ingest_projects(:'gh', '[{"key": "onyx", "name": "Onyx", "kind": "code", "status": "blocked", "next_step": "Call App Review"}]');
select tests.eq((select count(*)::int from dismissals where key = 'blocked:' || :'onyx'), 0, 'a new next step ends it');
select tests.login(:'admin');
select dismiss('blocked:' || :'onyx');
select tests.eq((select device_id from dismissals where key = 'blocked:' || :'onyx'), null::uuid, 'an admin dismisses too');
select tests.login_service();
select ingest_projects(:'gh', '[{"key": "onyx", "name": "Onyx", "kind": "code", "status": "active", "next_step": "Call App Review"}]');
select tests.eq((select count(*)::int from dismissals where key = 'blocked:' || :'onyx'), 0, 'unblocked ends it');
select tests.login(:'admin');
select dismiss('blocked:' || :'onyx');
select tests.login_service();
delete from projects where id = :'onyx';
select tests.eq((select count(*)::int from dismissals where key like 'blocked:%'), 0, 'a deleted project takes its dismissal with it');
select tests.eq((select count(*)::int from dismissals), 1, 'the metric one stays');
