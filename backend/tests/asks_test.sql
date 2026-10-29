-- Asks (20261029000010): an agent asks, the person answers on a display, in
-- the app, on the console or by asking McFly, and the agent reads it back.
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

-- Only the service role gets near the ingest and read functions.
select tests.ok(not has_function_privilege('authenticated', 'ingest_asks(uuid, jsonb)', 'execute'), 'ingest_asks is service only');
select tests.ok(not has_function_privilege('authenticated', 'agent_read_asks(uuid, text[], boolean)', 'execute'), 'agent_read_asks is service only');
select tests.ok(not has_function_privilege('anon', 'answer_ask(uuid, text, text)', 'execute'), 'anon cannot answer');
select tests.ok(has_function_privilege('authenticated', 'answer_ask(uuid, text, text)', 'execute'), 'a signed-in caller may try');

-- ───────────────────────────── Ingest ─────────────────────────────
select tests.login_service();
select ingest_asks(:'gh', jsonb_build_array(
  jsonb_build_object('id', 'ship-2.3', 'question', '  Ship v2.3 to TestFlight?  ', 'choices', '["Ship it", " Hold "]'::jsonb,
                     'detail', 'CI is green; 14 checks.', 'url', 'https://github.com/rmantilla13/mcfly/pull/40'),
  jsonb_build_object('question', 'Renew the domain?'),
  jsonb_build_object('id', 'headline', 'question', 'Which headline leads?', 'choices', '["A", "B", "C"]'::jsonb,
                     'expires_at', '2099-01-01T00:00:00Z'))) as r \gset
select tests.eq(jsonb_array_length(:'r'::jsonb), 3, 'one reply per ask');
select tests.eq((:'r'::jsonb)->0->>'id', 'ship-2.3', 'replies in order, by the agent''s own id');
select tests.eq((:'r'::jsonb)->0->>'status', 'open', 'open');
select tests.eq((select question from asks where external_id = 'ship-2.3'), 'Ship v2.3 to TestFlight?', 'question trimmed');
select tests.eq((select choices from asks where external_id = 'ship-2.3'), '["Ship it", "Hold"]'::jsonb, 'choices trimmed');
select tests.eq((select choices from asks where question = 'Renew the domain?'), '["Yes", "No"]'::jsonb, 'no choices: Yes and No');
select tests.ok((select length(external_id) = 36 from asks where question = 'Renew the domain?'), 'no id: one is made up');

select tests.throws($$select ingest_asks('00000000-0000-0000-0000-00000000a004', '[{"question": "x", "choices": ["Only"]}]')$$, 'ask x: give 2 to 4 choices', 'one choice');
select tests.throws($$select ingest_asks('00000000-0000-0000-0000-00000000a004', '[{"question": "x", "choices": ["a", "b", "c", "d", "e"]}]')$$, 'ask x: give 2 to 4 choices', 'five choices');
select tests.throws($$select ingest_asks('00000000-0000-0000-0000-00000000a004', '[{"question": "x", "choices": ["Yes", "yes"]}]')$$, 'ask x: choice yes is there twice', 'the same choice twice');
select tests.throws($$select ingest_asks('00000000-0000-0000-0000-00000000a004', '[{"question": "x", "choices": ["ok", "   "]}]')$$, 'ask x: each choice must be 1 to 32 characters', 'blank choice');
select tests.throws($$select ingest_asks('00000000-0000-0000-0000-00000000a004', '[{"question": "x", "choices": ["ok", 2]}]')$$, 'ask x: each choice must be a label', 'a number');
select tests.throws($$select ingest_asks('00000000-0000-0000-0000-00000000a004', '[{"question": "x", "choices": "ok"}]')$$, 'ask x: choices must be a list of labels', 'not a list');
select tests.throws($$select ingest_asks('00000000-0000-0000-0000-00000000a004', '[{"question": "  "}]')$$, 'each ask needs a question', 'blank question');
select tests.throws($$select ingest_asks('00000000-0000-0000-0000-00000000a004', '[{"id": "ship-2.3"}]')$$, 'each ask needs a question', 'an id alone');
select tests.throws($$select ingest_asks('00000000-0000-0000-0000-00000000a004', '[{"id": "nope", "withdrawn": true}]')$$, 'no ask nope: send its question', 'withdrawing one never asked');
select tests.throws($$select ingest_asks('00000000-0000-0000-0000-00000000a004', '[{"question": "x", "url": "ftp://x"}]')$$, 'ask x: url must be an http(s) URL', 'bad url');
select tests.throws($$select ingest_asks('00000000-0000-0000-0000-00000000a004', '[{"question": "x", "expires_at": "soon"}]')$$, 'ask x has an unreadable expires_at', 'bad expiry');
select tests.throws($$select ingest_asks('00000000-0000-0000-0000-00000000a004', '{"question": "x"}')$$, 'asks must be a list', 'not a list of asks');

-- A re-push changes an open ask; withdrawn takes it back and false asks again.
select ingest_asks(:'gh', '[{"id": "headline", "question": "Which headline leads tomorrow?", "choices": ["A", "B"]}]');
select tests.eq((select question || ' ' || choices::text || ' ' || (expires_at = '2099-01-01T00:00:00Z') from asks where external_id = 'headline'),
                'Which headline leads tomorrow? ["A", "B"] true', 'an open ask follows the re-push');
select ingest_asks(:'gh', '[{"id": "headline", "question": "Which headline leads tomorrow?", "detail": "Two drafts", "expires_at": null}]');
select tests.eq((select choices::text || ' ' || detail || ' ' || (expires_at is null) from asks where external_id = 'headline'),
                '["A", "B"] Two drafts true', 'what a re-push leaves out stays, and a null clears');
select (ingest_asks(:'gh', '[{"id": "headline", "withdrawn": true}]'))->0->>'status' as s \gset
select tests.eq(:'s'::text, 'withdrawn', 'withdrawn');
select (ingest_asks(:'gh', '[{"id": "headline", "question": "Which headline leads tomorrow?"}]'))->0->>'status' as s \gset
select tests.eq(:'s'::text, 'withdrawn', 'no withdrawn: unchanged');
select (ingest_asks(:'gh', '[{"id": "headline", "question": "Which headline leads tomorrow?", "withdrawn": false}]'))->0->>'status' as s \gset
select tests.eq(:'s'::text, 'open', 'withdrawn false: asked again');

-- ───────────────────────────── A display answers ─────────────────────────────
select id as ship from asks where external_id = 'ship-2.3' \gset
select id as headline from asks where external_id = 'headline' \gset
select id as domain from asks where question = 'Renew the domain?' \gset
select tests.login(:'device');
select tests.eq((select count(*)::int from asks), 3, 'a display reads them');
select tests.eq(tests.affected($$update asks set answer = 'Hold', answered_at = now(), answered_via = 'display'$$), 0, 'but cannot write them directly');
select tests.eq(tests.affected($$delete from asks$$), 0, 'nor delete them');
select tests.throws(format($$select answer_ask(%L, 'Maybe')$$, :'ship'), 'answer with one of: Ship it, Hold', 'not a choice');
select answer_ask(:'ship', '  ship IT ', 'console') as a \gset
select tests.eq((:'a'::jsonb)->>'answer', 'Ship it', 'the agent''s own label, whatever the case');
select tests.eq((:'a'::jsonb)->>'answered_via', 'display', 'a display is a display, whatever it says');
select tests.eq((:'a'::jsonb)->>'ask', :'ship', 'the row''s id comes back');
select tests.eq((select device_id::text from asks where id = :'ship'), '00000000-0000-0000-0000-00000000d001', 'which display');
select tests.eq((select answered_by from asks where id = :'ship'), :'device'::uuid, 'which sign-in');
select answered_at as first from asks where id = :'ship' \gset
select answer_ask(:'ship', 'Ship it');
select tests.eq((select answered_at from asks where id = :'ship'), :'first'::timestamptz, 'the same answer again changes nothing');
select tests.throws(format($$select answer_ask(%L, 'Hold')$$, :'ship'), 'already answered: Ship it', 'a different answer is refused');
select tests.throws($$select answer_ask('00000000-0000-0000-0000-000000000000', 'Yes')$$, 'ask not found', 'no such ask');

-- ───────────────────────────── The person, and McFly ─────────────────────────────
select tests.login(:'admin');
select (answer_ask(:'domain', 'yes', 'console'))->>'answered_via' as v \gset
select tests.eq(:'v'::text, 'console', 'the console says so');
select tests.login_service();
select (answer_ask(:'headline', 'b', 'console'))->>'answered_via' as v \gset
select tests.eq(:'v'::text, 'assistant', 'the service role is McFly answering when asked');
select ingest_asks(:'gh', '[{"question": "App or console?", "id": "which"}]');
select tests.login(:'admin');
select (answer_ask((select id from asks where external_id = 'which'), 'No'))->>'answered_via' as v \gset
select tests.eq(:'v'::text, 'app', 'an admin''s sign-in is the app unless it says console');

select tests.login(:'other');
select tests.throws(format($$select answer_ask(%L, 'Yes')$$, :'domain'), 'only a paired display or an admin can answer', 'a signed-in stranger');
select tests.eq((select count(*)::int from asks), 0, 'sees none');
select tests.login(null);
select tests.throws(format($$select answer_ask(%L, 'Yes')$$, :'domain'), '%permission denied%', 'anon may not call it');

-- ───────────────────────────── Withdrawn, run out, answered ─────────────────────────────
select tests.login_service();
select ingest_asks(:'gh', jsonb_build_array('{"id": "gone", "question": "Gone?", "withdrawn": true}'::jsonb,
  jsonb_build_object('id', 'late', 'question', 'Late?', 'expires_at', now() - interval '1 hour')));
select tests.login(:'device');
select tests.throws(format($$select answer_ask(%L, 'Yes')$$, (select id from asks where external_id = 'gone')), 'the agent took this question back', 'withdrawn');
select tests.throws(format($$select answer_ask(%L, 'Yes')$$, (select id from asks where external_id = 'late')), 'this question ran out', 'run out');

-- A re-push of an answered ask changes nothing and carries the answer.
select tests.login_service();
select (ingest_asks(:'gh', '[{"id": "ship-2.3", "question": "Ship v2.4 instead?", "choices": ["Yes", "No"], "withdrawn": true}]'))->0 as r \gset
select tests.eq((:'r'::jsonb)->>'status', 'answered', 'still answered');
select tests.eq((:'r'::jsonb)->>'answer', 'Ship it', 'the answer comes back on a re-push');
select tests.eq((select question || ' ' || choices::text from asks where id = :'ship'), 'Ship v2.3 to TestFlight? ["Ship it", "Hold"]', 'the question it was answered on stays');

-- ───────────────────────────── Reading back ─────────────────────────────
select tests.eq((select count(*)::int from agent_read_asks(:'gh')), 6, 'every ask of the agent');
select tests.eq((select count(*)::int from agent_read_asks(:'gh', open_only => true)), 0, 'none still open');
select tests.eq((select string_agg(r->>'answer', ',' order by r->>'answer') from agent_read_asks(:'gh', array['ship-2.3', 'headline']) r), 'B,Ship it', 'by id');
select tests.eq((select count(*)::int from agent_read_asks('00000000-0000-0000-0000-00000000a001')), 0, 'not another agent''s');
select tests.login(:'admin');
select tests.eq((select count(*)::int from asks), 6, 'an admin reads them');

-- ───────────────────────────── Pruning, revoking ─────────────────────────────
select tests.logout();
update asks set answered_at = now() - interval '31 days' where id = :'domain';
update asks set expires_at = now() - interval '31 days' where external_id = 'late';
select tests.login_service();
select ingest_asks(:'gh', '[{"id": "fresh", "question": "Fresh?"}]');
select tests.eq((select count(*)::int from asks where id = :'domain' or external_id = 'late'), 0, 'closed a month ago: gone');
select tests.eq((select count(*)::int from asks), 5, 'the rest stay');
select tests.logout();
delete from devices where id = '00000000-0000-0000-0000-00000000d001';
select tests.eq((select device_id from asks where id = :'ship'), null::uuid, 'a revoked display leaves its answers');
delete from agents where id = :'gh';
select tests.eq((select count(*)::int from asks), 0, 'deleting the agent takes its asks with it');
