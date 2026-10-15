-- McFly core schema: one person's agent display.
--
-- Agents (Grok, a stocks agent, the Daily Pulse pipeline, ...) push into
-- three feeds with an API key: briefs (text updates), quotes (stocks) and
-- news (a Daily Pulse report of sourced stories). Paired displays read the
-- feeds as their own device user; a platform admin runs it all from the
-- admin console. Every secret (agent key hashes) sits in a table without
-- policies, so only the service role can touch it.
--
-- Applied by the Supabase CLI (supabase db push) and by backend/tests/run.sh
-- on plain Postgres. Keep it runnable on both: no Storage, no Realtime here
-- (those go in 20261014000002_realtime.sql).

-- ───────────────────────── Admins and settings ─────────────────────────

create table public.platform_admins (
  user_id     uuid primary key references auth.users on delete cascade,
  created_at  timestamptz not null default now(),
  created_by  uuid
);

-- Exactly one row (id is always true).
create table public.platform_settings (
  id                 boolean primary key default true check (id),
  display_name       text not null default 'McFly',
  timezone           text not null default 'America/Chicago',
  briefs_keep_days   int not null default 30 check (briefs_keep_days between 1 and 3650),
  quotes_keep_days   int not null default 90 check (quotes_keep_days between 1 and 3650),
  news_keep_reports  int not null default 14 check (news_keep_reports between 1 and 1000),
  updated_at         timestamptz not null default now(),
  updated_by         uuid
);
insert into public.platform_settings default values;

-- The service role key counts as an admin too, so the edge functions can
-- call the admin RPCs.
create function public.is_service_role()
returns boolean
language sql stable set search_path = public as $$
  select coalesce(coalesce(nullif(current_setting('request.jwt.claim.role', true), ''),
                           nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'role') = 'service_role',
                  false)
$$;

create function public.is_platform_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.is_service_role(), false)
      or exists (select 1 from public.platform_admins where user_id = auth.uid())
$$;

-- ───────────────────────────── Accounts ─────────────────────────────

-- One row per person with an account (the iPhone and Mac apps sign in with
-- it). Device accounts (the displays) don't get one.
create table public.profiles (
  id            uuid primary key references auth.users on delete cascade,
  display_name  text not null default '',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- McFly is one person's. The first person to sign up becomes its admin;
-- anyone after that needs an admin to add them (admin_set_admin). Turn
-- sign-ups off in Supabase Auth once your account exists (docs/ADMIN.md).
create function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.raw_app_meta_data->>'kind' = 'device' then
    return new;
  end if;
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(nullif(btrim(new.raw_user_meta_data->>'display_name'), ''),
                           split_part(coalesce(new.email, ''), '@', 1), ''))
  on conflict (id) do nothing;
  if not exists (select 1 from public.platform_admins) then
    insert into public.platform_admins (user_id) values (new.id) on conflict (user_id) do nothing;
  end if;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ───────────────────────────── Displays ─────────────────────────────

-- Paired displays. Each one signs in as its own auth user, created by the
-- pair-device function when an admin claims its code.
create table public.devices (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null unique references auth.users on delete cascade,
  name          text not null default 'Display',
  last_seen_at  timestamptz,
  created_at    timestamptz not null default now()
);

-- Short-lived codes shown on an unpaired display. Only the pair-device
-- function (service role) touches this table: RLS on, no policies.
create table public.pairing_codes (
  code          text primary key,
  secret_hash   text not null,
  device_id     uuid references public.devices on delete cascade,
  claimed_by    uuid references auth.users on delete set null,
  expires_at    timestamptz not null default now() + interval '10 minutes',
  created_at    timestamptz not null default now()
);

create function public.is_device()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.devices where user_id = auth.uid())
$$;

-- Who may read the feeds: a paired display or an admin.
create function public.can_read()
returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_device() or public.is_platform_admin()
$$;

-- A display may only touch its own last_seen_at.
create function public.devices_guard()
returns trigger
language plpgsql set search_path = public as $$
begin
  if public.is_platform_admin() then
    return new;
  end if;
  if (new.id, new.user_id, new.name, new.created_at) is distinct from (old.id, old.user_id, old.name, old.created_at) then
    raise exception 'a display can only update its check-in time';
  end if;
  return new;
end $$;

create trigger devices_guard before update on public.devices
  for each row execute function public.devices_guard();

-- ───────────────────────────── Agents ─────────────────────────────

-- Who pushes. `kind` is a label for the console and the display (icon,
-- color); any agent may push to any feed.
create table public.agents (
  id            uuid primary key default gen_random_uuid(),
  name          text not null check (length(btrim(name)) between 1 and 80),
  slug          text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{0,39}$'),
  kind          text not null default 'other' check (kind in ('grok', 'stocks', 'news', 'other')),
  color         text not null default '#4F7CF7' check (color ~* '^#[0-9a-f]{6}$'),
  created_at    timestamptz not null default now(),
  created_by    uuid,
  last_seen_at  timestamptz,
  revoked_at    timestamptz
);

-- The API key, hashed. No policies: service role only. The key itself is
-- shown once, when it is made, and never stored.
create table public.agent_keys (
  agent_id    uuid primary key references public.agents on delete cascade,
  key_hash    text not null unique,
  key_prefix  text not null,            -- the first characters, for the console
  created_at  timestamptz not null default now()
);

-- What arrived, for the console's "last push" column and for debugging an
-- agent that stops showing up.
create table public.ingest_log (
  id          bigint generated always as identity primary key,
  agent_id    uuid references public.agents on delete cascade,
  feed        text not null,
  count       int not null default 0,
  status      text not null default 'ok' check (status in ('ok', 'error')),
  message     text,
  created_at  timestamptz not null default now()
);
create index on public.ingest_log (created_at desc);
create index on public.ingest_log (agent_id, created_at desc);

-- ───────────────────────────── Feeds ─────────────────────────────

-- Text updates: Grok's hourly and daily notes, alerts from any agent.
create table public.briefs (
  id            uuid primary key default gen_random_uuid(),
  agent_id      uuid not null references public.agents on delete cascade,
  external_id   text,                   -- the agent's own id; a re-push updates the row
  title         text not null check (length(title) between 1 and 200),
  body          text not null default '' check (length(body) <= 20000),
  kind          text not null default 'update' check (kind in ('hourly', 'daily', 'alert', 'update')),
  published_at  timestamptz not null default now(),
  expires_at    timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (agent_id, external_id)
);
create index on public.briefs (published_at desc);

-- Stock quotes, one row per push and symbol; the newest per symbol is what
-- the display shows, the older ones draw its sparkline.
create table public.quotes (
  id          bigint generated always as identity primary key,
  agent_id    uuid not null references public.agents on delete cascade,
  symbol      text not null check (symbol ~ '^[A-Z0-9.^=:-]{1,16}$'),
  name        text,
  price       numeric not null,
  change      numeric,
  change_pct  numeric,
  currency    text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  note        text check (length(note) <= 2000),
  data        jsonb not null default '{}',
  as_of       timestamptz not null default now(),
  created_at  timestamptz not null default now()
);
create index on public.quotes (symbol, as_of desc);

-- The symbols seen so far, in the order the display shows them. An agent's
-- push adds a row; the console sets the order and hides symbols.
create table public.symbols (
  symbol      text primary key,
  name        text,
  sort_order  int not null default 1000,
  hidden      boolean not null default false,
  updated_at  timestamptz not null default now()
);

create view public.quotes_latest with (security_invoker = true) as
  select distinct on (q.symbol) q.*
  from public.quotes q
  order by q.symbol, q.as_of desc, q.id desc;

-- A Daily Pulse report: the day's sourced stories by section.
create table public.news_reports (
  id            uuid primary key default gen_random_uuid(),
  agent_id      uuid not null references public.agents on delete cascade,
  slug          text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{0,63}$'),
  report_date   date not null,
  display_date  text,                   -- as the agent writes it, e.g. "Oct 14, 2026"
  hero_item     text,                   -- item key of the top story
  published_at  timestamptz not null default now(),
  created_at    timestamptz not null default now()
);
create index on public.news_reports (report_date desc);

create table public.news_items (
  id             uuid primary key default gen_random_uuid(),
  report_id      uuid not null references public.news_reports on delete cascade,
  section_key    text not null check (section_key ~ '^[a-z0-9_-]{1,32}$'),
  section_name   text not null check (length(section_name) between 1 and 80),
  section_order  int not null default 0,
  item_key       text not null check (item_key ~ '^[A-Za-z0-9_.-]{1,64}$'),
  position       int not null default 0,
  headline       text not null check (length(headline) between 1 and 300),
  takeaway       text not null default '' check (length(takeaway) <= 2000),
  url            text not null check (url ~* '^https?://'),
  image_url      text check (image_url is null or image_url ~* '^https?://'),
  source_domain  text,
  created_at     timestamptz not null default now(),
  unique (report_id, section_key, item_key)
);
create index on public.news_items (report_id, section_order, position);

-- ───────────────────────────── Triggers ─────────────────────────────

create function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger briefs_touch before update on public.briefs for each row execute function public.touch_updated_at();
create trigger profiles_touch before update on public.profiles for each row execute function public.touch_updated_at();

-- ───────────────────────────── Audit ─────────────────────────────

create table public.admin_audit_log (
  id           bigint generated always as identity primary key,
  admin_id     uuid,
  action       text not null,
  target_type  text,
  target_id    text,
  details      jsonb not null default '{}',
  created_at   timestamptz not null default now()
);
create index on public.admin_audit_log (created_at desc);

-- The acting admin is auth.uid(); rows written under the service role have
-- no admin_id.
create function public.log_admin_action(action text, target_type text, target_id text, details jsonb default '{}')
returns void
language sql security definer set search_path = public as $$
  insert into public.admin_audit_log (admin_id, action, target_type, target_id, details)
  values (auth.uid(), action, target_type, target_id, coalesce(details, '{}'))
$$;

-- ───────────────────────────── Ingest ─────────────────────────────
-- Called by the ingest edge function with the service role after it has
-- matched the agent's key. The payload shapes are docs/AGENTS.md; the
-- checks here are the last line, so a bad row never lands however it got in.

-- The host of a URL, for "source: blog.google" under a story.
create function public.url_host(url text)
returns text
language sql immutable as $$
  select lower(regexp_replace(substring(url from '^[a-zA-Z][a-zA-Z0-9+.-]*://([^/?#]+)'), '^www\.', ''))
$$;

-- An ISO timestamp from an agent, or `fallback` when it is missing or unreadable.
create function public.read_timestamp(value jsonb, fallback timestamptz)
returns timestamptz
language plpgsql immutable as $$
begin
  if value is null or jsonb_typeof(value) <> 'string' then
    return fallback;
  end if;
  return (value #>> '{}')::timestamptz;
exception when others then
  return fallback;
end $$;

-- briefs: [{ id?, title, body?, kind?, published_at?, expires_at? }]. Rows
-- with an id replace an earlier push with the same id. Returns how many landed.
create function public.ingest_briefs(agent uuid, items jsonb)
returns int
language plpgsql security definer set search_path = public as $$
declare
  item jsonb;
  n int := 0;
  k text;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  if jsonb_typeof(items) <> 'array' then raise exception 'briefs must be a list'; end if;
  if jsonb_array_length(items) > 200 then raise exception 'at most 200 briefs per push'; end if;
  for item in select * from jsonb_array_elements(items) loop
    if jsonb_typeof(item) <> 'object' then raise exception 'each brief must be an object'; end if;
    k := coalesce(nullif(btrim(item->>'kind'), ''), 'update');
    if k not in ('hourly', 'daily', 'alert', 'update') then
      raise exception 'kind must be hourly, daily, alert or update';
    end if;
    insert into public.briefs as b (agent_id, external_id, title, body, kind, published_at, expires_at)
    values (agent,
            nullif(left(btrim(item->>'id'), 120), ''),
            left(btrim(item->>'title'), 200),
            left(coalesce(item->>'body', ''), 20000),
            k,
            public.read_timestamp(item->'published_at', now()),
            public.read_timestamp(item->'expires_at', null))
    on conflict (agent_id, external_id) where external_id is not null do update
      set title = excluded.title, body = excluded.body, kind = excluded.kind,
          published_at = excluded.published_at, expires_at = excluded.expires_at;
    n := n + 1;
  end loop;
  return n;
end $$;

-- quotes: [{ symbol, name?, price, change?, change_pct?, currency?, note?, as_of?, data? }].
create function public.ingest_quotes(agent uuid, items jsonb, as_of_default timestamptz default now())
returns int
language plpgsql security definer set search_path = public as $$
declare
  item jsonb;
  n int := 0;
  sym text;
  when_at timestamptz;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  if jsonb_typeof(items) <> 'array' then raise exception 'quotes must be a list'; end if;
  if jsonb_array_length(items) > 500 then raise exception 'at most 500 quotes per push'; end if;
  for item in select * from jsonb_array_elements(items) loop
    if jsonb_typeof(item) <> 'object' then raise exception 'each quote must be an object'; end if;
    sym := upper(btrim(item->>'symbol'));
    if sym !~ '^[A-Z0-9.^=:-]{1,16}$' then raise exception 'symbol % is not usable', coalesce(item->>'symbol', ''); end if;
    if item->>'price' is null then raise exception 'quote % has no price', sym; end if;
    when_at := public.read_timestamp(item->'as_of', coalesce(as_of_default, now()));
    insert into public.quotes (agent_id, symbol, name, price, change, change_pct, currency, note, data, as_of)
    values (agent, sym,
            nullif(left(btrim(item->>'name'), 120), ''),
            (item->>'price')::numeric,
            (item->>'change')::numeric,
            (item->>'change_pct')::numeric,
            coalesce(upper(nullif(btrim(item->>'currency'), '')), 'USD'),
            nullif(left(item->>'note', 2000), ''),
            coalesce(case when jsonb_typeof(item->'data') = 'object' then item->'data' end, '{}'),
            when_at);
    insert into public.symbols as s (symbol, name)
    values (sym, nullif(left(btrim(item->>'name'), 120), ''))
    on conflict (symbol) do update set name = coalesce(excluded.name, s.name), updated_at = now();
    n := n + 1;
  end loop;
  return n;
end $$;

-- news: the Daily Pulse items JSON. { date, slug, hero?, sections: [{ key,
-- name, items: [{ id, h, t, url, image? }] }] }. A report with the same slug
-- is replaced whole. Returns the report id.
create function public.ingest_news(agent uuid, report jsonb)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  rid uuid;
  slug_in text := lower(btrim(report->>'slug'));
  day date;
  section jsonb;
  item jsonb;
  s_order int := 0;
  pos int;
  n int := 0;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  if jsonb_typeof(report) <> 'object' then raise exception 'the report must be an object'; end if;
  if slug_in !~ '^[a-z0-9][a-z0-9-]{0,63}$' then raise exception 'slug must be like 2026-10-14'; end if;
  if coalesce(jsonb_typeof(report->'sections'), 'null') <> 'array' or jsonb_array_length(report->'sections') = 0 then
    raise exception 'sections must be a non-empty list';
  end if;
  -- The slug is the file prefix in the Pulse pipeline, normally the date.
  begin
    day := coalesce((report->>'report_date')::date, substring(slug_in from '^\d{4}-\d{2}-\d{2}')::date);
  exception when others then
    day := null;
  end;
  if day is null then day := current_date; end if;

  delete from public.news_reports where slug = slug_in;
  insert into public.news_reports (agent_id, slug, report_date, display_date, hero_item, published_at)
  values (agent, slug_in, day, nullif(left(btrim(report->>'date'), 40), ''),
          nullif(left(btrim(report->>'hero'), 64), ''),
          public.read_timestamp(report->'published_at', now()))
  returning id into rid;

  for section in select * from jsonb_array_elements(report->'sections') loop
    if jsonb_typeof(section) <> 'object' or coalesce(jsonb_typeof(section->'items'), 'null') <> 'array' then
      raise exception 'each section needs a key, a name and items';
    end if;
    pos := 0;
    for item in select * from jsonb_array_elements(section->'items') loop
      if jsonb_typeof(item) <> 'object' then raise exception 'each item must be an object'; end if;
      insert into public.news_items (report_id, section_key, section_name, section_order, item_key, position,
                                     headline, takeaway, url, image_url, source_domain)
      values (rid,
              lower(left(btrim(section->>'key'), 32)),
              left(btrim(coalesce(nullif(section->>'name', ''), section->>'key')), 80),
              s_order,
              coalesce(nullif(left(btrim(item->>'id'), 64), ''), 'item-' || s_order || '-' || pos),
              pos,
              left(btrim(coalesce(item->>'h', item->>'headline')), 300),
              left(coalesce(item->>'t', item->>'takeaway', ''), 2000),
              btrim(item->>'url'),
              nullif(btrim(item->>'image'), ''),
              public.url_host(btrim(item->>'url')));
      pos := pos + 1;
      n := n + 1;
    end loop;
    s_order := s_order + 1;
  end loop;
  if n = 0 then raise exception 'the report has no items'; end if;
  if n > 500 then raise exception 'at most 500 items per report'; end if;
  return rid;
end $$;

-- Writes an ingest_log row and marks the agent seen.
create function public.record_ingest(agent uuid, feed text, count int, status text, message text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  insert into public.ingest_log (agent_id, feed, count, status, message)
  values (agent, left(feed, 32), coalesce(count, 0), status, left(message, 500));
  if status = 'ok' then
    update public.agents set last_seen_at = now() where id = agent;
  end if;
end $$;

-- Retention, from platform_settings: old briefs, old quote history (the
-- newest row per symbol always stays), old reports, old log rows.
create function public.prune_feed()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s public.platform_settings;
  briefs_gone int; quotes_gone int; reports_gone int; log_gone int;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  select * into s from public.platform_settings;
  delete from public.briefs
   where published_at < now() - make_interval(days => s.briefs_keep_days)
      or (expires_at is not null and expires_at < now() - interval '1 day');
  get diagnostics briefs_gone = row_count;
  delete from public.quotes q
   where q.as_of < now() - make_interval(days => s.quotes_keep_days)
     and q.id <> (select l.id from public.quotes l where l.symbol = q.symbol order by l.as_of desc, l.id desc limit 1);
  get diagnostics quotes_gone = row_count;
  delete from public.news_reports r
   where r.id not in (select id from public.news_reports order by report_date desc, published_at desc limit s.news_keep_reports);
  get diagnostics reports_gone = row_count;
  delete from public.ingest_log where created_at < now() - interval '90 days';
  get diagnostics log_gone = row_count;
  return jsonb_build_object('briefs', briefs_gone, 'quotes', quotes_gone, 'reports', reports_gone, 'log', log_gone);
end $$;

-- The agent behind a key hash, for the ingest function. Null when unknown
-- or revoked.
create function public.agent_for_key(hash text)
returns table (id uuid, name text, slug text, kind text)
language sql stable security definer set search_path = public as $$
  select a.id, a.name, a.slug, a.kind
  from public.agent_keys k join public.agents a on a.id = k.agent_id
  where k.key_hash = hash and a.revoked_at is null and public.is_platform_admin()
$$;

-- ───────────────────────────── Admin RPCs ─────────────────────────────
-- Behind the console. Each checks is_platform_admin() itself and every
-- change writes an audit row.

create function public.admin_overview()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return jsonb_build_object(
    'agents',           (select count(*) from public.agents where revoked_at is null),
    'agents_revoked',   (select count(*) from public.agents where revoked_at is not null),
    'pushes_24h',       (select count(*) from public.ingest_log where status = 'ok' and created_at >= now() - interval '24 hours'),
    'errors_24h',       (select count(*) from public.ingest_log where status = 'error' and created_at >= now() - interval '24 hours'),
    'briefs',           (select count(*) from public.briefs),
    'briefs_24h',       (select count(*) from public.briefs where published_at >= now() - interval '24 hours'),
    'symbols',          (select count(*) from public.symbols where not hidden),
    'quotes',           (select count(*) from public.quotes),
    'news_reports',     (select count(*) from public.news_reports),
    'latest_report',    (select slug from public.news_reports order by report_date desc, published_at desc limit 1),
    'devices',          (select count(*) from public.devices),
    'devices_online',   (select count(*) from public.devices where last_seen_at >= now() - interval '15 minutes'),
    'last_push_at',     (select max(created_at) from public.ingest_log where status = 'ok'));
end $$;

create function public.admin_list_agents()
returns table (id uuid, name text, slug text, kind text, color text, created_at timestamptz, last_seen_at timestamptz,
               revoked_at timestamptz, key_prefix text, key_created_at timestamptz, pushes_7d int, last_error text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query
    select a.id, a.name, a.slug, a.kind, a.color, a.created_at, a.last_seen_at, a.revoked_at,
           k.key_prefix, k.created_at,
           (select count(*)::int from public.ingest_log l where l.agent_id = a.id and l.status = 'ok'
              and l.created_at >= now() - interval '7 days'),
           (select l.message from public.ingest_log l where l.agent_id = a.id and l.status = 'error'
              order by l.created_at desc limit 1)
    from public.agents a
    left join public.agent_keys k on k.agent_id = a.id
    order by a.revoked_at nulls first, a.created_at, a.id;
end $$;

-- A new key: mcf_ plus 40 hex characters. Only its SHA-256 is kept.
create function public.new_agent_key()
returns text
language sql volatile set search_path = public as $$
  select 'mcf_' || encode(extensions.gen_random_bytes(20), 'hex')
$$;

create function public.key_hash(key text)
returns text
language sql immutable set search_path = public as $$
  select encode(extensions.digest(key, 'sha256'), 'hex')
$$;

create function public.slugify(name text)
returns text
language sql immutable as $$
  select left(btrim(regexp_replace(lower(name), '[^a-z0-9]+', '-', 'g'), '-'), 40)
$$;

-- Makes an agent and returns its key, the one time it is ever shown.
create function public.admin_create_agent(name text, kind text default 'other', color text default null)
returns table (id uuid, slug text, key text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  agent_name text := btrim(admin_create_agent.name);
  base text := public.slugify(admin_create_agent.name);
  new_slug text;
  new_id uuid;
  new_key text;
  i int := 0;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  if length(agent_name) < 1 or length(agent_name) > 80 then raise exception 'name must be 1 to 80 characters'; end if;
  if base = '' then base := 'agent'; end if;
  new_slug := base;
  while exists (select 1 from public.agents a where a.slug = new_slug) loop
    i := i + 1;
    new_slug := left(base, 36) || '-' || i;
  end loop;
  insert into public.agents (name, slug, kind, color, created_by)
  values (agent_name, new_slug, coalesce(nullif(btrim(admin_create_agent.kind), ''), 'other'),
          coalesce(nullif(btrim(admin_create_agent.color), ''), '#4F7CF7'), auth.uid())
  returning agents.id into new_id;
  new_key := public.new_agent_key();
  insert into public.agent_keys (agent_id, key_hash, key_prefix) values (new_id, public.key_hash(new_key), left(new_key, 12));
  perform public.log_admin_action('create_agent', 'agent', new_id::text,
                                  jsonb_build_object('name', agent_name, 'slug', new_slug, 'kind', admin_create_agent.kind));
  id := new_id;
  slug := new_slug;
  key := new_key;
  return next;
end $$;

-- Replaces the key. The old one stops working at once.
create function public.admin_rotate_agent_key(agent uuid)
returns text
language plpgsql security definer set search_path = public as $$
declare
  new_key text := public.new_agent_key();
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  if not exists (select 1 from public.agents a where a.id = agent) then raise exception 'agent not found'; end if;
  update public.agents a set revoked_at = null where a.id = agent;
  insert into public.agent_keys (agent_id, key_hash, key_prefix) values (agent, public.key_hash(new_key), left(new_key, 12))
  on conflict (agent_id) do update set key_hash = excluded.key_hash, key_prefix = excluded.key_prefix, created_at = now();
  perform public.log_admin_action('rotate_agent_key', 'agent', agent::text, '{}');
  return new_key;
end $$;

create function public.admin_update_agent(agent uuid, name text default null, kind text default null, color text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  update public.agents a
     set name  = coalesce(nullif(btrim(admin_update_agent.name), ''), a.name),
         kind  = coalesce(nullif(btrim(admin_update_agent.kind), ''), a.kind),
         color = coalesce(nullif(btrim(admin_update_agent.color), ''), a.color)
   where a.id = agent;
  if not found then raise exception 'agent not found'; end if;
  perform public.log_admin_action('update_agent', 'agent', agent::text,
                                  jsonb_strip_nulls(jsonb_build_object('name', admin_update_agent.name, 'kind', admin_update_agent.kind,
                                                                       'color', admin_update_agent.color)));
end $$;

-- Revoked: its key is gone and its pushes are refused. Its feed rows stay.
create function public.admin_revoke_agent(agent uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  update public.agents a set revoked_at = coalesce(a.revoked_at, now()) where a.id = agent;
  if not found then raise exception 'agent not found'; end if;
  delete from public.agent_keys k where k.agent_id = agent;
  perform public.log_admin_action('revoke_agent', 'agent', agent::text, '{}');
end $$;

-- Deletes the agent and everything it pushed.
create function public.admin_delete_agent(agent uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  a public.agents;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  select * into a from public.agents x where x.id = agent;
  if not found then raise exception 'agent not found'; end if;
  delete from public.agents x where x.id = agent;
  perform public.log_admin_action('delete_agent', 'agent', agent::text, jsonb_build_object('name', a.name, 'slug', a.slug));
end $$;

create function public.admin_list_briefs(lim int default 50, off int default 0)
returns table (id uuid, agent_id uuid, agent_name text, agent_color text, external_id text, title text, body text, kind text,
               published_at timestamptz, expires_at timestamptz, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query
    select b.id, b.agent_id, a.name, a.color, b.external_id, b.title, b.body, b.kind, b.published_at, b.expires_at, b.created_at
    from public.briefs b join public.agents a on a.id = b.agent_id
    order by b.published_at desc, b.id
    limit greatest(least(coalesce(lim, 50), 500), 1) offset greatest(coalesce(off, 0), 0);
end $$;

create function public.admin_delete_brief(brief uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  t text;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  delete from public.briefs b where b.id = brief returning b.title into t;
  if not found then raise exception 'brief not found'; end if;
  perform public.log_admin_action('delete_brief', 'brief', brief::text, jsonb_build_object('title', t));
end $$;

create function public.admin_list_quotes()
returns table (symbol text, name text, sort_order int, hidden boolean, price numeric, change numeric, change_pct numeric,
               currency text, note text, as_of timestamptz, agent_name text, agent_color text, history_count int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query
    select s.symbol, coalesce(s.name, l.name), s.sort_order, s.hidden, l.price, l.change, l.change_pct, l.currency, l.note, l.as_of,
           a.name, a.color, (select count(*)::int from public.quotes q where q.symbol = s.symbol)
    from public.symbols s
    left join public.quotes_latest l on l.symbol = s.symbol
    left join public.agents a on a.id = l.agent_id
    order by s.hidden, s.sort_order, s.symbol;
end $$;

create function public.admin_set_symbol(symbol text, hidden boolean default null, sort_order int default null, name text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  sym text := upper(btrim(admin_set_symbol.symbol));
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  update public.symbols s
     set hidden = coalesce(admin_set_symbol.hidden, s.hidden),
         sort_order = coalesce(admin_set_symbol.sort_order, s.sort_order),
         name = coalesce(nullif(btrim(admin_set_symbol.name), ''), s.name),
         updated_at = now()
   where s.symbol = sym;
  if not found then raise exception 'symbol not found'; end if;
  perform public.log_admin_action('set_symbol', 'symbol', sym,
                                  jsonb_strip_nulls(jsonb_build_object('hidden', admin_set_symbol.hidden,
                                                                       'sort_order', admin_set_symbol.sort_order,
                                                                       'name', admin_set_symbol.name)));
end $$;

-- Removes the symbol and all its quotes. An agent that pushes it again brings it back.
create function public.admin_delete_symbol(symbol text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  sym text := upper(btrim(admin_delete_symbol.symbol));
  n int;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  delete from public.quotes q where q.symbol = sym;
  get diagnostics n = row_count;
  delete from public.symbols s where s.symbol = sym;
  if not found then raise exception 'symbol not found'; end if;
  perform public.log_admin_action('delete_symbol', 'symbol', sym, jsonb_build_object('quotes_removed', n));
end $$;

create function public.admin_list_news_reports(lim int default 30)
returns table (id uuid, slug text, report_date date, display_date text, hero_item text, published_at timestamptz,
               agent_name text, agent_color text, item_count int, sections text[])
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query
    select r.id, r.slug, r.report_date, r.display_date, r.hero_item, r.published_at, a.name, a.color,
           (select count(*)::int from public.news_items i where i.report_id = r.id),
           (select coalesce(array_agg(distinct i.section_name order by i.section_name), '{}') from public.news_items i where i.report_id = r.id)
    from public.news_reports r join public.agents a on a.id = r.agent_id
    order by r.report_date desc, r.published_at desc
    limit greatest(least(coalesce(lim, 30), 500), 1);
end $$;

create function public.admin_news_report(report uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r public.news_reports;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  select * into r from public.news_reports x where x.id = report;
  if not found then raise exception 'report not found'; end if;
  return jsonb_build_object(
    'report', to_jsonb(r),
    'items', coalesce((select jsonb_agg(to_jsonb(i) order by i.section_order, i.position)
                       from public.news_items i where i.report_id = r.id), '[]'));
end $$;

create function public.admin_delete_news_report(report uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  s text;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  delete from public.news_reports r where r.id = report returning r.slug into s;
  if not found then raise exception 'report not found'; end if;
  perform public.log_admin_action('delete_news_report', 'news_report', report::text, jsonb_build_object('slug', s));
end $$;

create function public.admin_list_ingest(lim int default 50, off int default 0)
returns table (id bigint, created_at timestamptz, agent_id uuid, agent_name text, agent_color text, feed text, count int,
               status text, message text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query
    select l.id, l.created_at, l.agent_id, a.name, a.color, l.feed, l.count, l.status, l.message
    from public.ingest_log l left join public.agents a on a.id = l.agent_id
    order by l.id desc
    limit greatest(least(coalesce(lim, 50), 500), 1) offset greatest(coalesce(off, 0), 0);
end $$;

create function public.admin_list_devices()
returns table (id uuid, user_id uuid, name text, last_seen_at timestamptz, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query select d.id, d.user_id, d.name, d.last_seen_at, d.created_at from public.devices d order by d.created_at, d.id;
end $$;

create function public.admin_rename_device(device uuid, name text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  n text := left(btrim(admin_rename_device.name), 80);
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  if n = '' then raise exception 'name is required'; end if;
  update public.devices d set name = n where d.id = device;
  if not found then raise exception 'device not found'; end if;
  perform public.log_admin_action('rename_device', 'device', device::text, jsonb_build_object('name', n));
end $$;

-- Removes the display's row. Its auth user goes too when this role may
-- delete auth users; otherwise the admin edge function finishes the job.
create function public.admin_revoke_device(device uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  d public.devices;
  removed int := 0;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  select * into d from public.devices x where x.id = device;
  if not found then raise exception 'device not found'; end if;
  delete from public.devices x where x.id = device;
  begin
    delete from auth.users u where u.id = d.user_id;
    get diagnostics removed = row_count;
  exception when insufficient_privilege then
    null;
  end;
  perform public.log_admin_action('revoke_device', 'device', device::text,
                                  jsonb_build_object('name', d.name, 'auth_user_removed', removed > 0));
  return jsonb_build_object('user_id', d.user_id, 'auth_user_removed', removed > 0);
end $$;

create function public.admin_get_settings()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return (select to_jsonb(s) - 'id' from public.platform_settings s);
end $$;

-- Null arguments leave that setting as it is.
create function public.admin_update_settings(display_name text default null, timezone text default null,
                                             briefs_keep_days int default null, quotes_keep_days int default null,
                                             news_keep_reports int default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  changes jsonb := jsonb_strip_nulls(jsonb_build_object(
    'display_name', admin_update_settings.display_name, 'timezone', admin_update_settings.timezone,
    'briefs_keep_days', admin_update_settings.briefs_keep_days, 'quotes_keep_days', admin_update_settings.quotes_keep_days,
    'news_keep_reports', admin_update_settings.news_keep_reports));
  result jsonb;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  if admin_update_settings.timezone is not null and not exists (select 1 from pg_timezone_names where name = admin_update_settings.timezone) then
    raise exception 'timezone % is not known', admin_update_settings.timezone;
  end if;
  update public.platform_settings s
     set display_name      = coalesce(nullif(btrim(admin_update_settings.display_name), ''), s.display_name),
         timezone          = coalesce(admin_update_settings.timezone, s.timezone),
         briefs_keep_days  = coalesce(admin_update_settings.briefs_keep_days, s.briefs_keep_days),
         quotes_keep_days  = coalesce(admin_update_settings.quotes_keep_days, s.quotes_keep_days),
         news_keep_reports = coalesce(admin_update_settings.news_keep_reports, s.news_keep_reports),
         updated_at        = now(),
         updated_by        = auth.uid()
   where s.id
  returning to_jsonb(s) - 'id' into result;
  perform public.log_admin_action('update_settings', 'settings', null, changes);
  return result;
end $$;

create function public.admin_set_admin(target uuid, make_admin boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare
  u auth.users;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  if make_admin is null then raise exception 'make_admin is required'; end if;
  select * into u from auth.users x where x.id = target;
  if not found then raise exception 'user not found'; end if;
  lock table public.platform_admins in share row exclusive mode;
  if make_admin then
    if u.raw_app_meta_data->>'kind' = 'device' then raise exception 'a display account can''t be an admin'; end if;
    insert into public.platform_admins (user_id, created_by) values (target, auth.uid()) on conflict (user_id) do nothing;
  else
    if exists (select 1 from public.platform_admins a where a.user_id = target)
       and (select count(*) from public.platform_admins) = 1 then
      raise exception 'the last admin can''t be removed';
    end if;
    delete from public.platform_admins a where a.user_id = target;
  end if;
  perform public.log_admin_action('set_admin', 'user', target::text, jsonb_build_object('make_admin', make_admin, 'email', u.email));
end $$;

create function public.admin_list_audit(lim int default 100, off int default 0)
returns table (id bigint, created_at timestamptz, admin_email text, action text, target_type text, target_id text, details jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query
    select a.id, a.created_at, u.email::text, a.action, a.target_type, a.target_id, a.details
    from public.admin_audit_log a left join auth.users u on u.id = a.admin_id
    order by a.id desc
    limit greatest(least(coalesce(lim, 100), 500), 1) offset greatest(coalesce(off, 0), 0);
end $$;

-- ───────────────────────── Row-level security ─────────────────────────

alter table public.profiles          enable row level security;
alter table public.platform_admins   enable row level security;
alter table public.platform_settings enable row level security;
alter table public.devices           enable row level security;
alter table public.pairing_codes     enable row level security;
alter table public.agents            enable row level security;
alter table public.agent_keys        enable row level security;
alter table public.ingest_log        enable row level security;
alter table public.briefs            enable row level security;
alter table public.quotes            enable row level security;
alter table public.symbols           enable row level security;
alter table public.news_reports      enable row level security;
alter table public.news_items        enable row level security;
alter table public.admin_audit_log   enable row level security;

create policy platform_admins_read   on public.platform_admins   for select using (public.is_platform_admin());
-- A person sees and edits their own profile; admins see every profile.
create policy profiles_read   on public.profiles for select using (id = auth.uid() or public.is_platform_admin());
create policy profiles_update on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());
create policy platform_settings_read on public.platform_settings for select using (public.can_read());
create policy audit_read             on public.admin_audit_log   for select using (public.is_platform_admin());
create policy ingest_log_read        on public.ingest_log        for select using (public.is_platform_admin());

-- A display sees its own row and keeps its check-in time; admins see all.
create policy devices_read  on public.devices for select using (user_id = auth.uid() or public.is_platform_admin());
create policy devices_touch on public.devices for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- The feeds: displays and admins read; nothing writes but the functions above.
create policy agents_read       on public.agents       for select using (public.can_read());
create policy briefs_read       on public.briefs       for select using (public.can_read());
create policy quotes_read       on public.quotes       for select using (public.can_read());
create policy symbols_read      on public.symbols      for select using (public.can_read());
create policy news_reports_read on public.news_reports for select using (public.can_read());
create policy news_items_read   on public.news_items   for select using (public.can_read());

-- Internal functions aren't API.
revoke execute on function public.log_admin_action(text, text, text, jsonb) from public, anon, authenticated;
revoke execute on function public.devices_guard() from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.touch_updated_at() from public, anon, authenticated;
revoke execute on function public.new_agent_key() from public, anon, authenticated;
revoke execute on function public.key_hash(text) from public, anon, authenticated;
revoke execute on function public.agent_for_key(text) from public, anon, authenticated;
revoke execute on function public.ingest_briefs(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.ingest_quotes(uuid, jsonb, timestamptz) from public, anon, authenticated;
revoke execute on function public.ingest_news(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.record_ingest(uuid, text, int, text, text) from public, anon, authenticated;
revoke execute on function public.prune_feed() from public, anon;
-- Everything else is for signed-in callers (displays and admins); each admin
-- RPC refuses non-admins inside. Functions are executable by PUBLIC unless
-- that is taken away, so anon gets only the three checks.
revoke execute on all functions in schema public from public, anon;
grant execute on function public.is_platform_admin() to anon;
grant execute on function public.is_device() to anon;
grant execute on function public.can_read() to anon;
