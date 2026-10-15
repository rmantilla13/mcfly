-- Agent scopes and memory: only admins grant scopes and edit notes; displays
-- read notes; agents read and write through the service-only functions, and
-- only their own notes plus the shared ones.
\set ON_ERROR_STOP 1
\set grok     '00000000-0000-0000-0000-00000000a001'
\set stocks   '00000000-0000-0000-0000-00000000a002'
\set device   'd0000000-0000-0000-0000-000000000001'
\set stranger 'e0000000-0000-0000-0000-000000000001'
\set admin    'ad000000-0000-0000-0000-000000000001'

insert into auth.users (id, email, raw_app_meta_data) values
  (:'admin', 'admin@example.com', '{}'),
  (:'device', 'device-1@devices.mcfly.invalid', '{"kind": "device"}'),
  (:'stranger', 'stranger@example.com', '{}');
insert into devices (id, user_id, name) values ('00000000-0000-0000-0000-00000000d001', :'device', 'Kitchen');

-- ───────────────────────────── Who may call what ─────────────────────────────
select tests.ok(not has_function_privilege('anon', 'admin_set_agent_scopes(uuid, text[])', 'execute'), 'anon cannot grant scopes');
select tests.ok(not has_function_privilege('authenticated', 'agent_read_memory(uuid)', 'execute'), 'agent reads are service only');
select tests.ok(not has_function_privilege('authenticated', 'agent_write_memory(uuid, jsonb, text[])', 'execute'), 'agent writes are service only');
select tests.ok(not has_function_privilege('authenticated', 'agent_read_events(integer)', 'execute'), 'agent event reads are service only');

select tests.login(:'stranger');
select tests.throws(format('select admin_set_agent_scopes(%L, ''{memory:read}'')', :'grok'), 'admin only', 'stranger cannot grant');
select tests.throws('select * from admin_list_memories()', 'admin only', 'stranger cannot list notes');
select tests.throws('select admin_save_memory(text => ''x'')', 'admin only', 'stranger cannot write notes');
select tests.eq((select count(*)::int from memories), 0, 'stranger reads no notes');
select tests.login(:'device');
select tests.throws('select admin_save_memory(text => ''x'')', 'admin only', 'a display cannot write notes');

-- ───────────────────────────── Scopes ─────────────────────────────
select tests.login(:'admin');
select tests.eq((select scopes from admin_list_agents() where id = :'grok'), '{}'::text[], 'no scopes by default');
select tests.eq(admin_set_agent_scopes(:'grok', '{memory:write,memory:read,memory:read}'), '{memory:read,memory:write}'::text[],
                'scopes deduplicated and sorted');
select tests.throws(format('select admin_set_agent_scopes(%L, ''{root}'')', :'grok'), 'unknown scope%', 'unknown scope refused');
select tests.throws('select admin_set_agent_scopes(''99999999-9999-9999-9999-999999999999'', ''{}'')', 'agent not found', 'unknown agent');
select tests.eq((select details->'scopes' from admin_audit_log where action = 'set_agent_scopes'), '["memory:read", "memory:write"]'::jsonb,
                'grant audited');
select tests.login_service();
select tests.eq((select scopes from agent_for_key(key_hash('mcf_0000000000000000000000000000000000grok0'))), '{memory:read,memory:write}'::text[],
                'the key lookup carries the scopes');

-- ───────────────────────────── Notes ─────────────────────────────
select tests.login(:'admin');
select admin_save_memory(text => '  Ricky prefers metric units. ', pinned => true) as shared_note \gset
select admin_save_memory(text => 'Watch NVDA earnings.', agent => :'stocks') as stocks_note \gset
select tests.eq((select text from memories where id = :'shared_note'), 'Ricky prefers metric units.', 'stored trimmed');
select tests.eq((select count(*)::int from admin_list_memories()), 2, 'admin lists every note');
select tests.eq((select agent_name from admin_list_memories() where id = :'stocks_note'), 'Market desk', 'with its agent');
select admin_save_memory(id => :'shared_note', pinned => false);
select tests.eq((select pinned from memories where id = :'shared_note'), false, 'pin changed, text kept');
select tests.eq((select text from memories where id = :'shared_note'), 'Ricky prefers metric units.', 'text kept on a pin change');
select tests.throws('select admin_save_memory(text => '''')', 'a note is 1 to 2000 characters', 'empty note refused');
select tests.throws('select admin_save_memory(id => ''99999999-9999-9999-9999-999999999999'', text => ''x'')', 'note not found', 'unknown note');

select tests.login(:'device');
select tests.eq((select count(*)::int from memories), 2, 'a display reads every note');
select tests.throws('delete from memories', 'permission denied%', 'a display deletes nothing');

-- Agents, through the service role (the ingest function).
select tests.login_service();
select tests.eq((select count(*)::int from agent_read_memory(:'grok')), 1, 'grok sees the shared note only');
select tests.eq((select count(*)::int from agent_read_memory(:'stocks')), 2, 'stocks sees the shared note and its own');
select tests.eq(agent_write_memory(:'grok', '[{"key": "tone", "text": "Keep briefs short."}, {"text": "Ricky likes F1.", "shared": true}]'),
                '{"written": 2, "removed": 0}'::jsonb, 'grok writes its own note and a shared one');
select tests.eq(agent_write_memory(:'grok', '[{"key": "tone", "text": "Keep briefs very short."}]'),
                '{"written": 1, "removed": 0}'::jsonb, 'same key updates');
select tests.eq((select text from memories where agent_id = :'grok' and key = 'tone'), 'Keep briefs very short.', 'updated in place');
select tests.eq((select count(*)::int from memories where agent_id = :'grok'), 1, 'no duplicate for the same key');
select tests.eq((select source from memories where text = 'Ricky likes F1.'), 'agent', 'a shared note written by an agent says so');
-- An agent removes only its own keyed notes.
select agent_write_memory(:'stocks', '[{"key": "tone", "text": "Stocks tone."}]');
select tests.eq(agent_write_memory(:'grok', '[]', '{tone}'), '{"written": 0, "removed": 1}'::jsonb, 'grok removes its own');
select tests.eq((select count(*)::int from memories where key = 'tone'), 1, 'stocks''s note with the same key stays');
select tests.throws(format('select agent_write_memory(%L, ''[{"text": ""}]'')', :'grok'), 'a note is 1 to 2000 characters', 'empty refused');
select tests.throws(format('select agent_write_memory(%L, ''[{"key": "bad key!", "text": "x"}]'')', :'grok'), 'a note key is%', 'bad key');
select tests.throws(format('select agent_write_memory(%L, ''{"text": "x"}'')', :'grok'), 'memories must be a list', 'not a list');

-- Deleting an agent deletes its notes; shared ones stay.
select tests.login(:'admin');
select admin_delete_agent(:'stocks');
select tests.eq((select count(*)::int from memories where agent_id is not null), 0, 'agent notes went with it');
select tests.ok((select count(*) from memories where agent_id is null) >= 2, 'shared notes stay');
select admin_delete_memory(:'shared_note');
select tests.throws(format('select admin_delete_memory(%L)', :'shared_note'), 'note not found', 'deleting twice');
select tests.eq((select memory_count from admin_list_agents() where id = :'grok'), 0, 'note count on the agent list');

-- Events for agents with calendar:read: from now on, capped.
select tests.login_service();
select ingest_events(:'grok'::uuid, jsonb_build_array(
  jsonb_build_object('id', 'soon', 'title', 'Soon', 'starts_at', now() + interval '1 hour'),
  jsonb_build_object('id', 'old', 'title', 'Old', 'starts_at', now() - interval '3 days'),
  jsonb_build_object('id', 'far', 'title', 'Far', 'starts_at', now() + interval '30 days')), null);
select tests.eq((select array_agg(title order by starts_at) from agent_read_events(14) where title in ('Soon', 'Old', 'Far')),
                '{Soon}'::text[], 'two weeks, not the past');
select tests.eq((select count(*)::int from agent_read_events(60) where title in ('Soon', 'Old', 'Far')), 2, 'a longer window');

select 'memory_test passed';
