-- Todos and reminders, and McFly's own agent for what it is asked to add.
--
-- A todo is something to do, maybe by a day or a time; a reminder is
-- something to be told at a time. Both live in `todos` (kind todo · reminder)
-- and reach every screen like any feed: agents push them through ingest
-- (ingest_todos), displays and admins read them, nothing else writes.
--
-- The assistant adds events, todos and reminders when the person asks it to
-- (by voice or typing). It writes the way agents do, through the ingest
-- functions with the service role, as one built-in agent, "McFly", which has
-- no key, so nothing can push as it. The assistant function checks that its
-- caller may read (a paired display or an admin) before it writes; a display
-- still never writes on its own.
--
-- Everything here is new: no table or function from an earlier migration
-- changes.

-- ───────────────────────────── Todos ─────────────────────────────

create table if not exists public.todos (
  id           uuid primary key default gen_random_uuid(),
  agent_id     uuid not null references public.agents on delete cascade,
  external_id  text not null check (length(external_id) between 1 and 200),
  kind         text not null default 'todo' check (kind in ('todo', 'reminder')),
  title        text not null check (length(btrim(title)) between 1 and 300),
  notes        text check (length(notes) <= 2000),
  -- When it is due (a todo, optional) or when to remind (a reminder, always).
  -- With all_day, the day in the display's time zone, at its midnight.
  due_at       timestamptz,
  all_day      boolean not null default false,
  done_at      timestamptz,
  data         jsonb not null default '{}',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check (kind <> 'reminder' or (due_at is not null and not all_day)),
  check (due_at is not null or not all_day),
  unique (agent_id, external_id)
);
create index if not exists todos_open_idx on public.todos (due_at) where done_at is null;
create trigger todos_touch before update on public.todos for each row execute function public.touch_updated_at();

alter table public.todos enable row level security;
create policy todos_read on public.todos for select using (public.can_read());

-- ───────────────────────────── McFly's agent ─────────────────────────────

-- The agent that owns what the assistant adds: events (calendar "McFly") and
-- todos. Made on first use, like calendar_sources_agent().
create or replace function public.mcfly_agent()
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  agent uuid;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  select a.id into agent from public.agents a where a.slug = 'mcfly-assistant';
  if agent is null then
    insert into public.agents (name, slug, kind, color)
    values ('McFly', 'mcfly-assistant', 'other', '#F2A33A')
    on conflict (slug) do nothing
    returning id into agent;
    if agent is null then
      select a.id into agent from public.agents a where a.slug = 'mcfly-assistant';
    end if;
  end if;
  return agent;
end $$;

-- ───────────────────────────── Ingest ─────────────────────────────

-- todos: [{ id?, kind?, title, notes?, due_at?, all_day?, done?, data? }].
-- A re-push with the same id updates it; `done: true` checks it off (once:
-- a later push keeps the first time), `done: false` opens it again.
-- Returns the stored rows' ids, in order, so a caller can say which is which.
create or replace function public.ingest_todos(agent uuid, items jsonb)
returns uuid[]
language plpgsql security definer set search_path = public as $$
declare
  item jsonb;
  ids uuid[] := '{}';
  tid uuid;
  k text;
  t text;
  due timestamptz;
  all_day boolean;
  done boolean;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  if jsonb_typeof(items) <> 'array' then raise exception 'todos must be a list'; end if;
  if jsonb_array_length(items) > 200 then raise exception 'at most 200 todos per push'; end if;
  for item in select * from jsonb_array_elements(items) loop
    if jsonb_typeof(item) <> 'object' then raise exception 'each todo must be an object'; end if;
    t := left(btrim(coalesce(item->>'title', '')), 300);
    if t = '' then raise exception 'each todo needs a title'; end if;
    k := coalesce(nullif(btrim(item->>'kind'), ''), 'todo');
    if k not in ('todo', 'reminder') then raise exception 'todo % has an unknown kind (todo or reminder)', t; end if;
    due := public.read_timestamp(item->'due_at', null);
    if item ? 'due_at' and jsonb_typeof(item->'due_at') <> 'null' and due is null then
      raise exception 'todo % has an unreadable due_at', t;
    end if;
    all_day := coalesce((item->>'all_day')::boolean, false) and due is not null;
    if k = 'reminder' and due is null then raise exception 'reminder % needs due_at', t; end if;
    if k = 'reminder' and all_day then raise exception 'reminder % needs a time, not a whole day', t; end if;
    done := (item->>'done')::boolean;
    insert into public.todos as td (agent_id, external_id, kind, title, notes, due_at, all_day, done_at, data)
    values (agent,
            coalesce(nullif(left(btrim(item->>'id'), 200), ''), gen_random_uuid()::text),
            k, t,
            nullif(left(item->>'notes', 2000), ''),
            due, all_day,
            case when done then now() end,
            coalesce(case when jsonb_typeof(item->'data') = 'object' then item->'data' end, '{}'))
    on conflict (agent_id, external_id) do update
      set kind = excluded.kind, title = excluded.title, notes = excluded.notes, due_at = excluded.due_at,
          all_day = excluded.all_day, data = excluded.data,
          done_at = case when done is null then td.done_at when done then coalesce(td.done_at, now()) end
    returning td.id into tid;
    ids := ids || tid;
  end loop;
  return ids;
end $$;

-- Checks a todo off (or opens it again), whoever pushed it. For the
-- assistant ("I bought the milk") and the console.
create or replace function public.set_todo_done(todo uuid, done boolean)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  update public.todos t
     set done_at = case when done then coalesce(t.done_at, now()) end
   where t.id = todo;
  if not found then raise exception 'todo not found'; end if;
end $$;

revoke execute on function public.mcfly_agent() from public, anon, authenticated;
revoke execute on function public.ingest_todos(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.set_todo_done(uuid, boolean) from public, anon, authenticated;
