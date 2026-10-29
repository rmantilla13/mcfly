-- Asks: an agent asks the person something and reads the answer back.
--
-- An agent pushes a question with two to four choices ("Ship v2.3 to
-- TestFlight?" Ship it · Hold) through ingest (ingest_asks). It shows on the
-- display, in the app and on the console until it is answered, withdrawn by
-- the agent, or runs out (expires_at). The person answers with a tap, or by
-- asking McFly; the agent reads the answer with GET /ingest/asks
-- (agent_read_asks), or in the answer to its next push of the same id.
--
-- A paired display answers through answer_ask(), the third thing a display
-- may write after its own check-in and settings (and dismiss()). Who
-- answered (`answered_via`) is the server's to say, never the caller's:
-- display for a paired display, app or console for the person, assistant
-- for McFly answering when asked to (the service role).
--
-- Everything here is new: no table or function from an earlier migration
-- changes.

create table public.asks (
  id            uuid primary key default gen_random_uuid(),
  agent_id      uuid not null references public.agents on delete cascade,
  external_id   text not null check (length(external_id) between 1 and 200),
  question      text not null check (length(btrim(question)) between 1 and 300),
  detail        text check (length(detail) <= 2000),
  -- Two to four labels, each 1 to 32 characters, no two alike (any case).
  choices       jsonb not null check (jsonb_typeof(choices) = 'array' and jsonb_array_length(choices) between 2 and 4),
  url           text check (url ~* '^https?://'),
  expires_at    timestamptz,
  withdrawn_at  timestamptz,
  answer        text,
  answered_at   timestamptz,
  -- The auth user who answered: no reference, since a revoked display's goes.
  answered_by   uuid,
  device_id     uuid references public.devices on delete set null,
  answered_via  text check (answered_via in ('display', 'app', 'console', 'assistant')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check ((answer is null) = (answered_at is null)),
  check (answered_at is null or answered_via is not null),
  unique (agent_id, external_id)
);
create index asks_open_idx on public.asks (created_at) where answered_at is null and withdrawn_at is null;
create trigger asks_touch before update on public.asks for each row execute function public.touch_updated_at();

alter table public.asks enable row level security;
create policy asks_read on public.asks for select using (public.can_read());

-- Where an ask stands: answered, withdrawn, expired or open.
create function public.ask_status(a public.asks)
returns text
language sql stable set search_path = public as $$
  select case
    when a.answered_at is not null then 'answered'
    when a.withdrawn_at is not null then 'withdrawn'
    when a.expires_at is not null and a.expires_at <= now() then 'expired'
    else 'open'
  end
$$;

-- The choices an agent sent, checked: a list of 2 to 4 distinct labels, each
-- trimmed and 1 to 32 characters. None given means Yes and No.
create function public.ask_choices(value jsonb, question text)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  out jsonb := '[]';
  c jsonb;
  label text;
begin
  if value is null or jsonb_typeof(value) = 'null' then return '["Yes", "No"]'; end if;
  if jsonb_typeof(value) <> 'array' then raise exception 'ask %: choices must be a list of labels', question; end if;
  if jsonb_array_length(value) not between 2 and 4 then
    raise exception 'ask %: give 2 to 4 choices', question;
  end if;
  for c in select * from jsonb_array_elements(value) loop
    if jsonb_typeof(c) <> 'string' then raise exception 'ask %: each choice must be a label', question; end if;
    label := btrim(c #>> '{}');
    if length(label) not between 1 and 32 then
      raise exception 'ask %: each choice must be 1 to 32 characters', question;
    end if;
    if exists (select 1 from jsonb_array_elements_text(out) e where lower(e) = lower(label)) then
      raise exception 'ask %: choice % is there twice', question, label;
    end if;
    out := out || to_jsonb(label);
  end loop;
  return out;
end $$;

-- What an agent hears back about one of its asks.
create function public.ask_reply(a public.asks)
returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object(
    'id', a.external_id,
    'status', public.ask_status(a),
    'question', a.question,
    'choices', a.choices,
    'answer', a.answer,
    'answered_at', a.answered_at,
    'answered_via', a.answered_via,
    'asked_at', a.created_at,
    'expires_at', a.expires_at)
$$;

-- ───────────────────────────── Ingest ─────────────────────────────

-- asks: [{ id?, question, detail?, choices?, url?, expires_at?, withdrawn? }].
-- A re-push with the same id changes an ask nobody has answered yet: its
-- question, and whichever of detail, choices, link and expiry it sends (null
-- clears one). `withdrawn: true` takes it back (once), `false` asks it
-- again; { id, withdrawn } alone, with no question, does just that. An
-- answered ask stays as it was answered, so the answer always matches the
-- question. Returns each ask's ask_reply(), in order: a re-push is also a
-- way to read the answer. Closed asks (answered, withdrawn or run out) go
-- after 30 days.
create function public.ingest_asks(agent uuid, items jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  item jsonb;
  ext text;
  q text;
  url text;
  expires timestamptz;
  withdrawn boolean;
  row public.asks;
  out jsonb := '[]';
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  if jsonb_typeof(items) <> 'array' then raise exception 'asks must be a list'; end if;
  if jsonb_array_length(items) > 50 then raise exception 'at most 50 asks per push'; end if;
  for item in select * from jsonb_array_elements(items) loop
    if jsonb_typeof(item) <> 'object' then raise exception 'each ask must be an object'; end if;
    ext := nullif(left(btrim(item->>'id'), 200), '');
    withdrawn := (item->>'withdrawn')::boolean;
    q := left(btrim(coalesce(item->>'question', '')), 300);
    if q = '' then
      -- Only an id and withdrawn: take an ask back, or ask it again, as it is.
      if ext is null or withdrawn is null then raise exception 'each ask needs a question'; end if;
      update public.asks a
         set withdrawn_at = case when withdrawn then coalesce(a.withdrawn_at, now()) end
       where a.agent_id = agent and a.external_id = ext and a.answered_at is null
      returning a.* into row;
    else
      url := nullif(btrim(coalesce(item->>'url', '')), '');
      if url is not null and url !~* '^https?://\S+$' then raise exception 'ask %: url must be an http(s) URL', q; end if;
      expires := public.read_timestamp(item->'expires_at', null);
      if item ? 'expires_at' and jsonb_typeof(item->'expires_at') <> 'null' and expires is null then
        raise exception 'ask % has an unreadable expires_at', q;
      end if;
      insert into public.asks as a (agent_id, external_id, question, detail, choices, url, expires_at, withdrawn_at)
      values (agent, coalesce(ext, gen_random_uuid()::text), q,
              nullif(left(item->>'detail', 2000), ''),
              public.ask_choices(item->'choices', q),
              left(url, 2000), expires,
              case when withdrawn then now() end)
      on conflict (agent_id, external_id) do update
        set question = excluded.question,
            detail = case when item ? 'detail' then excluded.detail else a.detail end,
            choices = case when item ? 'choices' then excluded.choices else a.choices end,
            url = case when item ? 'url' then excluded.url else a.url end,
            expires_at = case when item ? 'expires_at' then excluded.expires_at else a.expires_at end,
            withdrawn_at = case when withdrawn is null then a.withdrawn_at when withdrawn then coalesce(a.withdrawn_at, now()) end
        where a.answered_at is null
      returning a.* into row;
    end if;
    -- Answered already, so nothing changed: the ask as it stands.
    if row.id is null then
      select a.* into row from public.asks a where a.agent_id = agent and a.external_id = ext;
      if row.id is null then raise exception 'no ask %: send its question', ext; end if;
    end if;
    out := out || jsonb_build_array(public.ask_reply(row));
    row := null;
  end loop;
  delete from public.asks a
   where coalesce(a.answered_at, a.withdrawn_at, case when a.expires_at <= now() then a.expires_at end)
         < now() - interval '30 days';
  return out;
end $$;

-- An agent's own asks, newest first: `ids` (its own ids) picks some, else
-- `open_only` picks the ones still waiting, else the last 100.
create function public.agent_read_asks(agent uuid, ids text[] default null, open_only boolean default false)
returns setof jsonb
language sql stable security definer set search_path = public as $$
  select public.ask_reply(a)
  from public.asks a
  where public.is_platform_admin()
    and a.agent_id = agent
    and (ids is null or a.external_id = any (ids))
    and (not open_only or public.ask_status(a) = 'open')
  order by a.created_at desc, a.id
  limit 100
$$;

-- ───────────────────────────── Answering ─────────────────────────────

-- Answer an open ask with one of its choices (any case; the agent's own
-- label is stored). A paired display, the person (an admin), or McFly when
-- asked (the service role) may. `via` says which of the person's screens
-- answered, the app (the default) or the console; it counts only for an
-- admin's own sign-in. The same answer again changes nothing; a different
-- one fails with "already answered: <label>", as does a withdrawn or
-- run-out ask with its own sentence. Two screens answering at once: one
-- wins, the other hears which.
create function public.answer_ask(ask uuid, choice text, via text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  a public.asks;
  label text;
  channel text;
  device uuid;
begin
  if public.is_device() then
    channel := 'display';
    select d.id into device from public.devices d where d.user_id = auth.uid();
  elsif public.is_service_role() then
    channel := 'assistant';
  elsif public.is_platform_admin() then
    channel := case when via = 'console' then 'console' else 'app' end;
  else
    raise exception 'only a paired display or an admin can answer';
  end if;

  select x.* into a from public.asks x where x.id = ask;
  if a.id is null then raise exception 'ask not found'; end if;
  select e into label from jsonb_array_elements_text(a.choices) e
   where lower(e) = lower(btrim(coalesce(choice, '')));
  if label is null then
    raise exception 'answer with one of: %', (select string_agg(e, ', ') from jsonb_array_elements_text(a.choices) e);
  end if;

  update public.asks x
     set answer = label, answered_at = now(), answered_by = auth.uid(), device_id = device, answered_via = channel
   where x.id = ask and x.answered_at is null and x.withdrawn_at is null
     and (x.expires_at is null or x.expires_at > now())
  returning x.* into a;
  if found then return public.ask_reply(a) || jsonb_build_object('ask', a.id); end if;

  select x.* into a from public.asks x where x.id = ask;
  if a.answered_at is not null and a.answer = label then
    return public.ask_reply(a) || jsonb_build_object('ask', a.id);
  end if;
  if a.answered_at is not null then raise exception 'already answered: %', a.answer; end if;
  if a.withdrawn_at is not null then raise exception 'the agent took this question back'; end if;
  raise exception 'this question ran out';
end $$;

revoke execute on function public.ingest_asks(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.agent_read_asks(uuid, text[], boolean) from public, anon, authenticated;
revoke execute on function public.answer_ask(uuid, text, text) from public, anon;
grant execute on function public.answer_ask(uuid, text, text) to authenticated;
