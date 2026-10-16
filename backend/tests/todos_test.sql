-- Todos and reminders: ingest (agents and the assistant), what displays see,
-- checking off, and McFly's own agent.
\set ON_ERROR_STOP 1
\set device 'd0000000-0000-0000-0000-000000000001'
\set admin  'ad000000-0000-0000-0000-000000000001'
insert into auth.users (id, email, raw_app_meta_data) values
  (:'admin', 'admin@example.com', '{}'),
  (:'device', 'device-1@devices.mcfly.invalid', '{"kind": "device"}');
insert into devices (id, user_id, name) values ('00000000-0000-0000-0000-00000000d001', :'device', 'Kitchen');

-- Only the service role (and admins) get near the write functions.
select tests.ok(not has_function_privilege('authenticated', 'ingest_todos(uuid, jsonb)', 'execute'), 'ingest_todos is service only');
select tests.ok(not has_function_privilege('authenticated', 'set_todo_done(uuid, boolean)', 'execute'), 'set_todo_done is service only');
select tests.ok(not has_function_privilege('authenticated', 'mcfly_agent()', 'execute'), 'mcfly_agent is service only');
select tests.ok(not has_function_privilege('anon', 'ingest_todos(uuid, jsonb)', 'execute'), 'anon cannot ingest todos');

-- ───────────────────────────── McFly's agent ─────────────────────────────
select tests.login_service();
select mcfly_agent() as mcfly \gset
select tests.eq(mcfly_agent(), :'mcfly'::uuid, 'the same agent every time');
select tests.eq((select name from agents where id = :'mcfly'), 'McFly', 'named McFly');
select tests.ok(not exists (select 1 from agent_keys where agent_id = :'mcfly'), 'it has no key');

-- ───────────────────────────── Ingest ─────────────────────────────
select ingest_todos(:'mcfly', jsonb_build_array(
  jsonb_build_object('title', '  Buy milk  '),
  jsonb_build_object('kind', 'reminder', 'title', 'Call mom', 'due_at', '2026-11-02T23:00:00Z', 'data', '{"via": "assistant"}'::jsonb),
  jsonb_build_object('id', 'tax', 'title', 'File taxes', 'due_at', '2026-11-02T06:00:00Z', 'all_day', true, 'notes', 'the extension'))) as ids \gset
select tests.eq(cardinality(:'ids'::uuid[]), 3, 'three ids back');
select tests.eq((select title from todos where id = (:'ids'::uuid[])[1]), 'Buy milk', 'title trimmed, ids in order');
select tests.eq((select kind from todos where id = (:'ids'::uuid[])[2]), 'reminder', 'a reminder');
select tests.eq((select data->>'via' from todos where title = 'Call mom'), 'assistant', 'data kept');
select tests.eq((select all_day from todos where external_id = 'tax'), true, 'due on a day');
select tests.ok((select length(external_id) = 36 from todos where title = 'Buy milk'), 'no id: one is made up');

-- A re-push with the same id updates; done checks it off once.
select ingest_todos(:'mcfly', '[{"id": "tax", "title": "File taxes", "done": true}]');
select tests.ok((select done_at is not null and due_at is null and not all_day from todos where external_id = 'tax'), 'updated and done');
select done_at as first_done from todos where external_id = 'tax' \gset
select ingest_todos(:'mcfly', '[{"id": "tax", "title": "File taxes", "done": true}]');
select tests.eq((select done_at from todos where external_id = 'tax'), :'first_done'::timestamptz, 'done keeps the first time');
select ingest_todos(:'mcfly', '[{"id": "tax", "title": "File taxes"}]');
select tests.ok((select done_at is not null from todos where external_id = 'tax'), 'no done: unchanged');
select ingest_todos(:'mcfly', '[{"id": "tax", "title": "File taxes", "done": false}]');
select tests.ok((select done_at is null from todos where external_id = 'tax'), 'done false: open again');

select tests.throws($$select ingest_todos(mcfly_agent(), '[{"kind": "reminder", "title": "x"}]')$$, 'reminder x needs due_at', 'reminder without a time');
select tests.throws($$select ingest_todos(mcfly_agent(), '[{"kind": "reminder", "title": "x", "due_at": "2026-11-02T06:00:00Z", "all_day": true}]')$$,
                    'reminder x needs a time, not a whole day', 'reminder for a whole day');
select tests.throws($$select ingest_todos(mcfly_agent(), '[{"title": "x", "due_at": "soon"}]')$$, 'todo x has an unreadable due_at', 'bad due_at');
select tests.throws($$select ingest_todos(mcfly_agent(), '[{"title": "  "}]')$$, 'each todo needs a title', 'blank title');
select tests.throws($$select ingest_todos(mcfly_agent(), '[{"title": "x", "kind": "chore"}]')$$, 'todo x has an unknown kind%', 'unknown kind');
select tests.throws($$select ingest_todos(mcfly_agent(), '{"title": "x"}')$$, 'todos must be a list', 'not a list');
select ingest_todos(:'mcfly', '[{"id": "z", "title": "z", "all_day": true}]');
select tests.eq((select all_day from todos where external_id = 'z'), false, 'all_day needs a day');

-- ───────────────────────────── Checking off ─────────────────────────────
select set_todo_done((:'ids'::uuid[])[1], true);
select tests.ok((select done_at is not null from todos where id = (:'ids'::uuid[])[1]), 'checked off');
select set_todo_done((:'ids'::uuid[])[1], false);
select tests.ok((select done_at is null from todos where id = (:'ids'::uuid[])[1]), 'opened again');
select tests.throws($$select set_todo_done('00000000-0000-0000-0000-000000000000', true)$$, 'todo not found', 'unknown todo');

-- ───────────────────────────── Displays read ─────────────────────────────
select tests.login(:'device');
select tests.eq((select count(*)::int from todos), 4, 'device reads todos');
select tests.throws($$insert into todos (agent_id, external_id, title) values ('00000000-0000-0000-0000-00000000a004', 'x', 'x')$$,
                    '%row-level security%', 'device cannot write todos');
select tests.eq(tests.affected($$delete from todos$$), 0, 'device cannot delete todos');
select tests.eq(tests.affected($$update todos set done_at = now()$$), 0, 'device cannot check todos off');
select tests.throws($$select set_todo_done('00000000-0000-0000-0000-000000000000', true)$$, 'permission denied%', 'nor through the function');
select tests.throws($$select ingest_todos('00000000-0000-0000-0000-00000000a004', '[{"title": "x"}]')$$, 'permission denied%', 'nor push');

select tests.login(:'admin');
select tests.eq((select count(*)::int from todos), 4, 'admin reads todos');
select tests.login(null);
select tests.eq((select count(*)::int from todos), 0, 'anon sees nothing');

-- Deleting the agent takes its todos with it.
select tests.logout();
delete from agents where id = :'mcfly';
select tests.eq((select count(*)::int from todos), 0, 'todos go with their agent');
