-- Agents get permissions, and McFly gets a memory.
--
-- Scopes: what an agent may read back through ingest, beyond pushing feeds
-- (which every agent may do). Off by default; the admin grants them.
--   memory:read    GET  /ingest/memory   the shared notes and the agent's own
--   memory:write   POST /ingest/memory   keep its own notes (and add shared ones)
--   calendar:read  GET  /ingest/events   the upcoming events from every calendar
--
-- Memory: short notes, either about the user (agent_id null, "shared") or an
-- agent's own working notes. The admin edits all of them; displays read them;
-- the assistant reads them as background (labelled data, never instructions);
-- agents with the scopes read and write through ingest.
--
-- Everything here adds to what is there: no column changes type, nothing is
-- renamed, and functions whose result gains a column are dropped and made
-- again with the same arguments.

-- ───────────────────────────── Scopes ─────────────────────────────

alter table public.agents add column if not exists scopes text[] not null default '{}';
alter table public.agents drop constraint if exists agents_scopes_known;
alter table public.agents add constraint agents_scopes_known
  check (scopes <@ array['memory:read', 'memory:write', 'calendar:read']::text[]);

-- The ingest function's lookup now says what the key may do.
drop function if exists public.agent_for_key(text);
create function public.agent_for_key(hash text)
returns table (id uuid, name text, slug text, kind text, scopes text[])
language sql stable security definer set search_path = public as $$
  select a.id, a.name, a.slug, a.kind, a.scopes
  from public.agent_keys k join public.agents a on a.id = k.agent_id
  where k.key_hash = hash and a.revoked_at is null and public.is_platform_admin()
$$;
revoke execute on function public.agent_for_key(text) from public, anon, authenticated;

drop function if exists public.admin_list_agents();
create function public.admin_list_agents()
returns table (id uuid, name text, slug text, kind text, color text, created_at timestamptz, last_seen_at timestamptz,
               revoked_at timestamptz, key_prefix text, key_created_at timestamptz, pushes_7d int, last_error text,
               scopes text[], memory_count int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query
    select a.id, a.name, a.slug, a.kind, a.color, a.created_at, a.last_seen_at, a.revoked_at,
           k.key_prefix, k.created_at,
           (select count(*)::int from public.ingest_log l where l.agent_id = a.id and l.status = 'ok'
              and l.created_at >= now() - interval '7 days'),
           (select l.message from public.ingest_log l where l.agent_id = a.id and l.status = 'error'
              order by l.created_at desc limit 1),
           a.scopes,
           (select count(*)::int from public.memories m where m.agent_id = a.id)
    from public.agents a
    left join public.agent_keys k on k.agent_id = a.id
    order by a.revoked_at nulls first, a.created_at, a.id;
end $$;
revoke execute on function public.admin_list_agents() from public, anon;
grant execute on function public.admin_list_agents() to authenticated;

create function public.admin_set_agent_scopes(agent uuid, scopes text[])
returns text[]
language plpgsql security definer set search_path = public as $$
declare
  clean text[];
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  select coalesce(array_agg(distinct s order by s), '{}') into clean
  from unnest(coalesce(admin_set_agent_scopes.scopes, '{}')) s;
  if not clean <@ array['memory:read', 'memory:write', 'calendar:read']::text[] then
    raise exception 'unknown scope (allowed: memory:read, memory:write, calendar:read)';
  end if;
  update public.agents a set scopes = clean where a.id = agent;
  if not found then raise exception 'agent not found'; end if;
  perform public.log_admin_action('set_agent_scopes', 'agent', agent::text, jsonb_build_object('scopes', clean));
  return clean;
end $$;
revoke execute on function public.admin_set_agent_scopes(uuid, text[]) from public, anon;
grant execute on function public.admin_set_agent_scopes(uuid, text[]) to authenticated;

-- ───────────────────────────── Memory ─────────────────────────────

create table if not exists public.memories (
  id          uuid primary key default gen_random_uuid(),
  agent_id    uuid references public.agents on delete cascade,  -- null: a shared note about the user
  key         text check (key is null or key ~ '^[A-Za-z0-9._:-]{1,80}$'),  -- an agent's own handle, for updates
  text        text not null check (length(btrim(text)) between 1 and 2000),
  pinned      boolean not null default false,
  source      text not null default 'admin' check (source in ('admin', 'agent')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists memories_agent_key on public.memories (agent_id, key) where key is not null;
create index if not exists memories_recent on public.memories (pinned desc, updated_at desc);

alter table public.memories enable row level security;
drop policy if exists memories_read on public.memories;
create policy memories_read on public.memories for select using (public.can_read());
revoke insert, update, delete on public.memories from anon, authenticated;
grant select on public.memories to authenticated;

-- At most 500 notes in all; the assistant reads the newest few.
create or replace function public.memories_cap()
returns trigger language plpgsql set search_path = public as $$
begin
  if (select count(*) from public.memories) >= 500 then
    raise exception 'memory is full (500 notes); delete some first';
  end if;
  return new;
end $$;
drop trigger if exists memories_cap on public.memories;
create trigger memories_cap before insert on public.memories for each row execute function public.memories_cap();

create function public.admin_list_memories()
returns table (id uuid, agent_id uuid, agent_name text, agent_color text, key text, text text, pinned boolean,
               source text, created_at timestamptz, updated_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query
    select m.id, m.agent_id, a.name, a.color, m.key, m.text, m.pinned, m.source, m.created_at, m.updated_at
    from public.memories m left join public.agents a on a.id = m.agent_id
    order by m.pinned desc, m.updated_at desc, m.id;
end $$;

-- Adds a note (id null) or changes one. agent null: a shared note.
create function public.admin_save_memory(id uuid default null, text text default null, pinned boolean default null,
                                         agent uuid default null)
returns uuid
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  saved uuid;
  body text := btrim(admin_save_memory.text);
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  if admin_save_memory.id is null then
    if body is null or length(body) < 1 or length(body) > 2000 then raise exception 'a note is 1 to 2000 characters'; end if;
    insert into public.memories (agent_id, text, pinned, source)
    values (admin_save_memory.agent, body, coalesce(admin_save_memory.pinned, false), 'admin')
    returning memories.id into saved;
  else
    if body is not null and (length(body) < 1 or length(body) > 2000) then raise exception 'a note is 1 to 2000 characters'; end if;
    update public.memories m
       set text = coalesce(body, m.text), pinned = coalesce(admin_save_memory.pinned, m.pinned), updated_at = now()
     where m.id = admin_save_memory.id
     returning m.id into saved;
    if saved is null then raise exception 'note not found'; end if;
  end if;
  perform public.log_admin_action('save_memory', 'memory', saved::text,
                                  jsonb_strip_nulls(jsonb_build_object('pinned', admin_save_memory.pinned)));
  return saved;
end $$;

create function public.admin_delete_memory(memory uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  delete from public.memories m where m.id = memory;
  if not found then raise exception 'note not found'; end if;
  perform public.log_admin_action('delete_memory', 'memory', memory::text, '{}');
end $$;

-- What an agent with memory:read sees: the shared notes and its own.
create function public.agent_read_memory(agent uuid)
returns table (id uuid, key text, text text, pinned boolean, shared boolean, updated_at timestamptz)
language sql stable security definer set search_path = public as $$
  select m.id, m.key, m.text, m.pinned, m.agent_id is null, m.updated_at
  from public.memories m
  where public.is_platform_admin() and (m.agent_id is null or m.agent_id = agent)
  order by m.pinned desc, m.updated_at desc
  limit 200
$$;

-- An agent with memory:write keeps its own notes by key (upsert), may add
-- shared notes (never change or delete ones it didn't write), and deletes
-- its own by key. Returns how many notes it wrote and deleted.
create function public.agent_write_memory(agent uuid, items jsonb, remove text[] default '{}')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  item jsonb;
  written int := 0;
  removed int := 0;
  body text;
  note_key text;
begin
  if not public.is_platform_admin() then raise exception 'service only'; end if;
  if jsonb_typeof(coalesce(items, '[]'::jsonb)) <> 'array' then raise exception 'memories must be a list'; end if;
  if jsonb_array_length(coalesce(items, '[]'::jsonb)) > 50 then raise exception 'at most 50 notes per push'; end if;
  for item in select * from jsonb_array_elements(coalesce(items, '[]'::jsonb)) loop
    body := btrim(item->>'text');
    note_key := nullif(btrim(item->>'key'), '');
    if body is null or length(body) < 1 or length(body) > 2000 then raise exception 'a note is 1 to 2000 characters'; end if;
    if note_key is not null and note_key !~ '^[A-Za-z0-9._:-]{1,80}$' then
      raise exception 'a note key is 1 to 80 letters, digits, dots, colons, dashes or underscores';
    end if;
    if coalesce((item->>'shared')::boolean, false) then
      insert into public.memories (agent_id, text, source) values (null, body, 'agent');
    elsif note_key is null then
      insert into public.memories (agent_id, text, source) values (agent, body, 'agent');
    else
      insert into public.memories (agent_id, key, text, source) values (agent, note_key, body, 'agent')
      on conflict (agent_id, key) where key is not null do update set text = excluded.text, updated_at = now();
    end if;
    written := written + 1;
  end loop;
  delete from public.memories m where m.agent_id = agent and m.key = any (coalesce(remove, '{}'));
  get diagnostics removed = row_count;
  return jsonb_build_object('written', written, 'removed', removed);
end $$;

revoke execute on function public.agent_read_memory(uuid) from public, anon, authenticated;
revoke execute on function public.agent_write_memory(uuid, jsonb, text[]) from public, anon, authenticated;
revoke execute on function public.admin_list_memories() from public, anon;
revoke execute on function public.admin_save_memory(uuid, text, boolean, uuid) from public, anon;
revoke execute on function public.admin_delete_memory(uuid) from public, anon;
grant execute on function public.admin_list_memories() to authenticated;
grant execute on function public.admin_save_memory(uuid, text, boolean, uuid) to authenticated;
grant execute on function public.admin_delete_memory(uuid) to authenticated;
revoke execute on function public.memories_cap() from public, anon, authenticated;

-- Upcoming events for an agent with calendar:read (the next two weeks).
create function public.agent_read_events(days int default 14)
returns table (id uuid, calendar text, title text, location text, starts_at timestamptz, ends_at timestamptz,
               all_day boolean, url text)
language sql stable security definer set search_path = public as $$
  select e.id, e.calendar, e.title, e.location, e.starts_at, e.ends_at, e.all_day, e.url
  from public.events e
  where public.is_platform_admin()
    and e.ends_at >= now()
    and e.starts_at < now() + make_interval(days => least(greatest(coalesce(days, 14), 1), 60))
  order by e.starts_at
  limit 500
$$;
revoke execute on function public.agent_read_events(int) from public, anon, authenticated;
