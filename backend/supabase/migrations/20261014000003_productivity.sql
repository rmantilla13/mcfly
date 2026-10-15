-- McFly's productivity feeds: projects (and their status updates), metrics,
-- agent-built dashboards and calendar events, plus the choice of assistant.
-- Same rules as the core: agents write through the ingest functions, paired
-- displays and admins read, nothing else sees a row.

-- ───────────────────────────── Settings ─────────────────────────────

alter table public.platform_settings
  add column assistant_provider text not null default 'claude' check (assistant_provider in ('claude', 'grok')),
  add column metrics_keep_days  int not null default 90 check (metrics_keep_days between 1 and 3650),
  add column events_keep_days   int not null default 60 check (events_keep_days between 1 and 3650);

-- ───────────────────────────── Projects ─────────────────────────────

-- What the person is working on, as the agents report it: a repository's
-- pull requests and CI, a client project, a launch. `key` is the agent's
-- own id; a re-push updates the project in place.
create table public.projects (
  id          uuid primary key default gen_random_uuid(),
  agent_id    uuid not null references public.agents on delete cascade,
  key         text not null check (key ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,119}$'),
  name        text not null check (length(name) between 1 and 120),
  kind        text not null default 'other' check (kind in ('code', 'task', 'launch', 'other')),
  status      text not null default 'active' check (status in ('active', 'blocked', 'paused', 'done')),
  progress    int check (progress between 0 and 100),
  summary     text not null default '' check (length(summary) <= 2000),
  next_step   text check (length(next_step) <= 500),
  link        text check (link is null or link ~* '^https?://'),
  color       text check (color is null or color ~* '^#[0-9a-f]{6}$'),
  data        jsonb not null default '{}',
  sort_order  int not null default 1000,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (agent_id, key)
);
create index on public.projects (status, sort_order);

-- The project's history, newest first: commits, pull requests, CI runs,
-- deploys, notes.
create table public.project_updates (
  id           bigint generated always as identity primary key,
  project_id   uuid not null references public.projects on delete cascade,
  kind         text not null default 'note' check (kind in ('note', 'commit', 'pr', 'ci', 'deploy', 'alert', 'done')),
  text         text not null check (length(text) between 1 and 2000),
  url          text check (url is null or url ~* '^https?://'),
  happened_at  timestamptz not null default now(),
  created_at   timestamptz not null default now()
);
create index on public.project_updates (project_id, happened_at desc);

create trigger projects_touch before update on public.projects for each row execute function public.touch_updated_at();

-- ───────────────────────────── Metrics ─────────────────────────────

-- Named numbers over time: sales today, open tickets, steps, a server's
-- load. One row per push; the newest per key is what shows, the history is
-- its sparkline.
create table public.metrics (
  id          bigint generated always as identity primary key,
  agent_id    uuid not null references public.agents on delete cascade,
  key         text not null check (key ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  label       text,
  value       numeric not null,
  unit        text check (length(unit) <= 16),
  delta       numeric,
  delta_pct   numeric,
  note        text check (length(note) <= 2000),
  data        jsonb not null default '{}',
  as_of       timestamptz not null default now(),
  created_at  timestamptz not null default now()
);
create index on public.metrics (key, as_of desc);

-- The metrics seen so far, in display order; the console groups, orders and hides.
create table public.metric_settings (
  key         text primary key,
  label       text,
  group_name  text,
  sort_order  int not null default 1000,
  hidden      boolean not null default false,
  updated_at  timestamptz not null default now()
);

create view public.metrics_latest with (security_invoker = true) as
  select distinct on (m.key) m.*
  from public.metrics m
  order by m.key, m.as_of desc, m.id desc;

-- ───────────────────────────── Dashboards ─────────────────────────────

-- A dashboard an agent lays out itself: a title and a list of widgets
-- (metric, status, progress, list, text, chart), rendered by the display and
-- the apps. A re-push replaces the whole dashboard.
create table public.dashboards (
  id          uuid primary key default gen_random_uuid(),
  agent_id    uuid not null references public.agents on delete cascade,
  key         text not null unique check (key ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  title       text not null check (length(title) between 1 and 80),
  subtitle    text check (length(subtitle) <= 200),
  widgets     jsonb not null check (jsonb_typeof(widgets) = 'array' and jsonb_array_length(widgets) between 1 and 40),
  sort_order  int not null default 1000,
  hidden      boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger dashboards_touch before update on public.dashboards for each row execute function public.touch_updated_at();

-- ───────────────────────────── Calendar ─────────────────────────────

-- Events, as agents push them (a calendar agent mirrors Google, iCloud or a
-- calendar link). `calendar` names the calendar they belong to; an agent's
-- push for a calendar can replace that calendar whole, so removed events go.
create table public.events (
  id           uuid primary key default gen_random_uuid(),
  agent_id     uuid not null references public.agents on delete cascade,
  calendar     text not null default 'Calendar' check (length(calendar) between 1 and 80),
  external_id  text not null check (length(external_id) between 1 and 200),
  title        text not null check (length(title) between 1 and 300),
  description  text check (length(description) <= 4000),
  location     text check (length(location) <= 300),
  starts_at    timestamptz not null,
  ends_at      timestamptz not null,
  all_day      boolean not null default false,
  color        text check (color is null or color ~* '^#[0-9a-f]{6}$'),
  url          text check (url is null or url ~* '^https?://'),
  data         jsonb not null default '{}',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check (ends_at >= starts_at),
  unique (agent_id, calendar, external_id)
);
create index on public.events (starts_at);
create trigger events_touch before update on public.events for each row execute function public.touch_updated_at();

-- ───────────────────────────── Ingest ─────────────────────────────

-- projects: [{ key, name, kind?, status?, progress?, summary?, next_step?,
-- link?, color?, sort_order?, data?, updates?: [{ kind?, text, url?, at? }] }]
create function public.ingest_projects(agent uuid, items jsonb)
returns int
language plpgsql security definer set search_path = public as $$
declare
  item jsonb;
  u jsonb;
  pid uuid;
  n int := 0;
  k int;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  if jsonb_typeof(items) <> 'array' then raise exception 'projects must be a list'; end if;
  if jsonb_array_length(items) > 100 then raise exception 'at most 100 projects per push'; end if;
  for item in select * from jsonb_array_elements(items) loop
    if jsonb_typeof(item) <> 'object' then raise exception 'each project must be an object'; end if;
    insert into public.projects as p (agent_id, key, name, kind, status, progress, summary, next_step, link, color, sort_order, data)
    values (agent,
            btrim(item->>'key'),
            left(btrim(coalesce(item->>'name', item->>'key')), 120),
            coalesce(nullif(btrim(item->>'kind'), ''), 'other'),
            coalesce(nullif(btrim(item->>'status'), ''), 'active'),
            (item->>'progress')::int,
            left(coalesce(item->>'summary', ''), 2000),
            nullif(left(item->>'next_step', 500), ''),
            nullif(btrim(item->>'link'), ''),
            nullif(btrim(item->>'color'), ''),
            coalesce((item->>'sort_order')::int, 1000),
            coalesce(case when jsonb_typeof(item->'data') = 'object' then item->'data' end, '{}'))
    on conflict (agent_id, key) do update
      set name = excluded.name, kind = excluded.kind, status = excluded.status, progress = excluded.progress,
          summary = excluded.summary, next_step = excluded.next_step, link = excluded.link,
          color = coalesce(excluded.color, p.color), sort_order = excluded.sort_order, data = excluded.data
    returning p.id into pid;
    if jsonb_typeof(item->'updates') = 'array' then
      k := 0;
      for u in select * from jsonb_array_elements(item->'updates') loop
        exit when k >= 20;
        if jsonb_typeof(u) = 'object' and nullif(btrim(u->>'text'), '') is not null then
          -- The same line again (an agent re-sending its log) is not a new update.
          if not exists (select 1 from public.project_updates x where x.project_id = pid
                           and x.text = left(btrim(u->>'text'), 2000)
                           and x.happened_at = public.read_timestamp(u->'at', now())) then
            insert into public.project_updates (project_id, kind, text, url, happened_at)
            values (pid, coalesce(nullif(btrim(u->>'kind'), ''), 'note'), left(btrim(u->>'text'), 2000),
                    nullif(btrim(u->>'url'), ''), public.read_timestamp(u->'at', now()));
          end if;
          k := k + 1;
        end if;
      end loop;
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;

-- metrics: [{ key, label?, value, unit?, delta?, delta_pct?, note?, as_of?, group?, data? }]
create function public.ingest_metrics(agent uuid, items jsonb, as_of_default timestamptz default now())
returns int
language plpgsql security definer set search_path = public as $$
declare
  item jsonb;
  n int := 0;
  k text;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  if jsonb_typeof(items) <> 'array' then raise exception 'metrics must be a list'; end if;
  if jsonb_array_length(items) > 500 then raise exception 'at most 500 metrics per push'; end if;
  for item in select * from jsonb_array_elements(items) loop
    if jsonb_typeof(item) <> 'object' then raise exception 'each metric must be an object'; end if;
    k := lower(btrim(item->>'key'));
    if k !~ '^[a-z0-9][a-z0-9._-]{0,63}$' then raise exception 'metric key % is not usable', coalesce(item->>'key', ''); end if;
    if item->>'value' is null then raise exception 'metric % has no value', k; end if;
    insert into public.metrics (agent_id, key, label, value, unit, delta, delta_pct, note, data, as_of)
    values (agent, k, nullif(left(btrim(item->>'label'), 80), ''), (item->>'value')::numeric,
            nullif(left(btrim(item->>'unit'), 16), ''), (item->>'delta')::numeric, (item->>'delta_pct')::numeric,
            nullif(left(item->>'note', 2000), ''),
            coalesce(case when jsonb_typeof(item->'data') = 'object' then item->'data' end, '{}'),
            public.read_timestamp(item->'as_of', coalesce(as_of_default, now())));
    insert into public.metric_settings as s (key, label, group_name)
    values (k, nullif(left(btrim(item->>'label'), 80), ''), nullif(left(btrim(item->>'group'), 80), ''))
    on conflict (key) do update
      set label = coalesce(excluded.label, s.label), group_name = coalesce(excluded.group_name, s.group_name), updated_at = now();
    n := n + 1;
  end loop;
  return n;
end $$;

-- dashboards: [{ key, title, subtitle?, sort_order?, widgets: [{ type, ... }] }]
create function public.ingest_dashboards(agent uuid, items jsonb)
returns int
language plpgsql security definer set search_path = public as $$
declare
  item jsonb;
  w jsonb;
  n int := 0;
  k text;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  if jsonb_typeof(items) <> 'array' then raise exception 'dashboards must be a list'; end if;
  if jsonb_array_length(items) > 20 then raise exception 'at most 20 dashboards per push'; end if;
  for item in select * from jsonb_array_elements(items) loop
    if jsonb_typeof(item) <> 'object' then raise exception 'each dashboard must be an object'; end if;
    k := lower(btrim(item->>'key'));
    if k !~ '^[a-z0-9][a-z0-9._-]{0,63}$' then raise exception 'dashboard key % is not usable', coalesce(item->>'key', ''); end if;
    if coalesce(jsonb_typeof(item->'widgets'), 'null') <> 'array' then raise exception 'dashboard % needs widgets', k; end if;
    for w in select * from jsonb_array_elements(item->'widgets') loop
      if jsonb_typeof(w) <> 'object' or coalesce(w->>'type', '') not in ('metric', 'status', 'progress', 'list', 'text', 'chart') then
        raise exception 'dashboard %: each widget needs a type of metric, status, progress, list, text or chart', k;
      end if;
    end loop;
    insert into public.dashboards as d (agent_id, key, title, subtitle, widgets, sort_order)
    values (agent, k, left(btrim(coalesce(nullif(item->>'title', ''), k)), 80), nullif(left(item->>'subtitle', 200), ''),
            item->'widgets', coalesce((item->>'sort_order')::int, 1000))
    on conflict (key) do update
      set agent_id = excluded.agent_id, title = excluded.title, subtitle = excluded.subtitle,
          widgets = excluded.widgets, sort_order = excluded.sort_order;
    n := n + 1;
  end loop;
  return n;
end $$;

-- events: [{ id, calendar?, title, starts_at, ends_at?, all_day?, description?,
-- location?, color?, url?, data? }]. With `replace_calendar`, that calendar's
-- other events from this agent are removed: the push is the whole calendar.
create function public.ingest_events(agent uuid, items jsonb, replace_calendar text default null)
returns int
language plpgsql security definer set search_path = public as $$
declare
  item jsonb;
  n int := 0;
  cal text;
  s timestamptz;
  e timestamptz;
  all_day boolean;
  kept text[] := '{}';
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  if jsonb_typeof(items) <> 'array' then raise exception 'events must be a list'; end if;
  if jsonb_array_length(items) > 1000 then raise exception 'at most 1000 events per push'; end if;
  for item in select * from jsonb_array_elements(items) loop
    if jsonb_typeof(item) <> 'object' then raise exception 'each event must be an object'; end if;
    cal := coalesce(nullif(left(btrim(item->>'calendar'), 80), ''), nullif(left(btrim(replace_calendar), 80), ''), 'Calendar');
    s := public.read_timestamp(item->'starts_at', null);
    if s is null then raise exception 'event % needs starts_at', coalesce(item->>'title', item->>'id', ''); end if;
    all_day := coalesce((item->>'all_day')::boolean, false);
    e := public.read_timestamp(item->'ends_at', null);
    if e is null then e := case when all_day then s + interval '1 day' - interval '1 second' else s + interval '1 hour' end; end if;
    insert into public.events as ev (agent_id, calendar, external_id, title, description, location, starts_at, ends_at, all_day, color, url, data)
    values (agent, cal,
            coalesce(nullif(left(btrim(item->>'id'), 200), ''), encode(extensions.digest(coalesce(item->>'title', '') || s::text, 'sha256'), 'hex')),
            left(btrim(item->>'title'), 300),
            nullif(left(item->>'description', 4000), ''),
            nullif(left(btrim(item->>'location'), 300), ''),
            s, e, all_day,
            nullif(btrim(item->>'color'), ''),
            nullif(btrim(item->>'url'), ''),
            coalesce(case when jsonb_typeof(item->'data') = 'object' then item->'data' end, '{}'))
    on conflict (agent_id, calendar, external_id) do update
      set title = excluded.title, description = excluded.description, location = excluded.location,
          starts_at = excluded.starts_at, ends_at = excluded.ends_at, all_day = excluded.all_day,
          color = excluded.color, url = excluded.url, data = excluded.data
    returning ev.external_id into cal; -- reuse: the stored id
    kept := kept || cal;
    n := n + 1;
  end loop;
  if replace_calendar is not null then
    delete from public.events ev
     where ev.agent_id = agent and ev.calendar = left(btrim(replace_calendar), 80)
       and not (ev.external_id = any (kept));
  end if;
  return n;
end $$;

-- Retention for the new feeds, called from prune_feed.
create function public.prune_productivity()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s public.platform_settings;
  metrics_gone int; events_gone int; updates_gone int;
begin
  select * into s from public.platform_settings;
  delete from public.metrics m
   where m.as_of < now() - make_interval(days => s.metrics_keep_days)
     and m.id <> (select l.id from public.metrics l where l.key = m.key order by l.as_of desc, l.id desc limit 1);
  get diagnostics metrics_gone = row_count;
  delete from public.events where ends_at < now() - make_interval(days => s.events_keep_days);
  get diagnostics events_gone = row_count;
  -- A project keeps its last 200 updates.
  delete from public.project_updates u
   where u.id in (select x.id from (select id, row_number() over (partition by project_id order by happened_at desc, id desc) as rn
                                    from public.project_updates) x where x.rn > 200);
  get diagnostics updates_gone = row_count;
  return jsonb_build_object('metrics', metrics_gone, 'events', events_gone, 'updates', updates_gone);
end $$;

create or replace function public.prune_feed()
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
  return jsonb_build_object('briefs', briefs_gone, 'quotes', quotes_gone, 'reports', reports_gone, 'log', log_gone)
         || public.prune_productivity();
end $$;

-- ───────────────────────────── Admin RPCs ─────────────────────────────

create or replace function public.admin_overview()
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
    'projects',         (select count(*) from public.projects where status <> 'done'),
    'projects_blocked', (select count(*) from public.projects where status = 'blocked'),
    'metrics',          (select count(*) from public.metric_settings where not hidden),
    'dashboards',       (select count(*) from public.dashboards where not hidden),
    'events_upcoming',  (select count(*) from public.events where ends_at >= now() and starts_at < now() + interval '7 days'),
    'devices',          (select count(*) from public.devices),
    'devices_online',   (select count(*) from public.devices where last_seen_at >= now() - interval '15 minutes'),
    'last_push_at',     (select max(created_at) from public.ingest_log where status = 'ok'));
end $$;

create function public.admin_list_projects()
returns table (id uuid, agent_id uuid, agent_name text, agent_color text, key text, name text, kind text, status text, progress int,
               summary text, next_step text, link text, color text, sort_order int, updated_at timestamptz, update_count int,
               last_update text, last_update_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query
    select p.id, p.agent_id, a.name, a.color, p.key, p.name, p.kind, p.status, p.progress, p.summary, p.next_step, p.link, p.color,
           p.sort_order, p.updated_at,
           (select count(*)::int from public.project_updates u where u.project_id = p.id),
           (select u.text from public.project_updates u where u.project_id = p.id order by u.happened_at desc, u.id desc limit 1),
           (select u.happened_at from public.project_updates u where u.project_id = p.id order by u.happened_at desc, u.id desc limit 1)
    from public.projects p join public.agents a on a.id = p.agent_id
    order by (p.status = 'done'), p.sort_order, p.updated_at desc;
end $$;

create function public.admin_project_updates(project uuid, lim int default 50)
returns table (id bigint, kind text, text text, url text, happened_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query
    select u.id, u.kind, u.text, u.url, u.happened_at from public.project_updates u
    where u.project_id = project order by u.happened_at desc, u.id desc
    limit greatest(least(coalesce(lim, 50), 500), 1);
end $$;

create function public.admin_delete_project(project uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  n text;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  delete from public.projects p where p.id = project returning p.name into n;
  if not found then raise exception 'project not found'; end if;
  perform public.log_admin_action('delete_project', 'project', project::text, jsonb_build_object('name', n));
end $$;

create function public.admin_list_metrics()
returns table (key text, label text, group_name text, sort_order int, hidden boolean, value numeric, unit text, delta numeric,
               delta_pct numeric, note text, as_of timestamptz, agent_name text, agent_color text, history_count int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query
    select s.key, coalesce(s.label, l.label, s.key), s.group_name, s.sort_order, s.hidden, l.value, l.unit, l.delta, l.delta_pct, l.note, l.as_of,
           a.name, a.color, (select count(*)::int from public.metrics m where m.key = s.key)
    from public.metric_settings s
    left join public.metrics_latest l on l.key = s.key
    left join public.agents a on a.id = l.agent_id
    order by s.hidden, s.group_name nulls last, s.sort_order, s.key;
end $$;

create function public.admin_set_metric(metric text, hidden boolean default null, sort_order int default null, label text default null,
                                        group_name text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  k text := lower(btrim(metric));
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  update public.metric_settings s
     set hidden = coalesce(admin_set_metric.hidden, s.hidden),
         sort_order = coalesce(admin_set_metric.sort_order, s.sort_order),
         label = coalesce(nullif(btrim(admin_set_metric.label), ''), s.label),
         group_name = coalesce(nullif(btrim(admin_set_metric.group_name), ''), s.group_name),
         updated_at = now()
   where s.key = k;
  if not found then raise exception 'metric not found'; end if;
  perform public.log_admin_action('set_metric', 'metric', k,
                                  jsonb_strip_nulls(jsonb_build_object('hidden', admin_set_metric.hidden, 'sort_order', admin_set_metric.sort_order,
                                                                       'label', admin_set_metric.label, 'group_name', admin_set_metric.group_name)));
end $$;

create function public.admin_delete_metric(metric text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  k text := lower(btrim(metric));
  n int;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  delete from public.metrics m where m.key = k;
  get diagnostics n = row_count;
  delete from public.metric_settings s where s.key = k;
  if not found then raise exception 'metric not found'; end if;
  perform public.log_admin_action('delete_metric', 'metric', k, jsonb_build_object('rows_removed', n));
end $$;

create function public.admin_list_dashboards()
returns table (id uuid, key text, title text, subtitle text, widgets jsonb, sort_order int, hidden boolean, updated_at timestamptz,
               agent_name text, agent_color text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query
    select d.id, d.key, d.title, d.subtitle, d.widgets, d.sort_order, d.hidden, d.updated_at, a.name, a.color
    from public.dashboards d join public.agents a on a.id = d.agent_id
    order by d.hidden, d.sort_order, d.title;
end $$;

create function public.admin_set_dashboard(dashboard uuid, hidden boolean default null, sort_order int default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  update public.dashboards d
     set hidden = coalesce(admin_set_dashboard.hidden, d.hidden),
         sort_order = coalesce(admin_set_dashboard.sort_order, d.sort_order)
   where d.id = dashboard;
  if not found then raise exception 'dashboard not found'; end if;
  perform public.log_admin_action('set_dashboard', 'dashboard', dashboard::text,
                                  jsonb_strip_nulls(jsonb_build_object('hidden', admin_set_dashboard.hidden, 'sort_order', admin_set_dashboard.sort_order)));
end $$;

create function public.admin_delete_dashboard(dashboard uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  k text;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  delete from public.dashboards d where d.id = dashboard returning d.key into k;
  if not found then raise exception 'dashboard not found'; end if;
  perform public.log_admin_action('delete_dashboard', 'dashboard', dashboard::text, jsonb_build_object('key', k));
end $$;

create function public.admin_list_events(days_back int default 7, days_ahead int default 60)
returns table (id uuid, agent_id uuid, agent_name text, calendar text, external_id text, title text, location text,
               starts_at timestamptz, ends_at timestamptz, all_day boolean, color text, url text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query
    select e.id, e.agent_id, a.name, e.calendar, e.external_id, e.title, e.location, e.starts_at, e.ends_at, e.all_day, e.color, e.url
    from public.events e join public.agents a on a.id = e.agent_id
    where e.ends_at >= now() - make_interval(days => greatest(coalesce(days_back, 7), 0))
      and e.starts_at < now() + make_interval(days => greatest(coalesce(days_ahead, 60), 1))
    order by e.starts_at, e.id;
end $$;

create function public.admin_delete_event(event uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  t text;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  delete from public.events e where e.id = event returning e.title into t;
  if not found then raise exception 'event not found'; end if;
  perform public.log_admin_action('delete_event', 'event', event::text, jsonb_build_object('title', t));
end $$;

-- Removes one calendar of one agent, every event in it.
create function public.admin_delete_calendar(agent uuid, calendar text)
returns int
language plpgsql security definer set search_path = public as $$
declare
  n int;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  delete from public.events e where e.agent_id = agent and e.calendar = btrim(admin_delete_calendar.calendar);
  get diagnostics n = row_count;
  perform public.log_admin_action('delete_calendar', 'calendar', btrim(admin_delete_calendar.calendar),
                                  jsonb_build_object('agent', agent, 'events_removed', n));
  return n;
end $$;

-- The settings RPC gains the assistant's provider and the new retention.
drop function public.admin_update_settings(text, text, int, int, int);
create function public.admin_update_settings(display_name text default null, timezone text default null,
                                             briefs_keep_days int default null, quotes_keep_days int default null,
                                             news_keep_reports int default null, assistant_provider text default null,
                                             metrics_keep_days int default null, events_keep_days int default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  changes jsonb := jsonb_strip_nulls(jsonb_build_object(
    'display_name', admin_update_settings.display_name, 'timezone', admin_update_settings.timezone,
    'briefs_keep_days', admin_update_settings.briefs_keep_days, 'quotes_keep_days', admin_update_settings.quotes_keep_days,
    'news_keep_reports', admin_update_settings.news_keep_reports, 'assistant_provider', admin_update_settings.assistant_provider,
    'metrics_keep_days', admin_update_settings.metrics_keep_days, 'events_keep_days', admin_update_settings.events_keep_days));
  result jsonb;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  if admin_update_settings.timezone is not null and not exists (select 1 from pg_timezone_names where name = admin_update_settings.timezone) then
    raise exception 'timezone % is not known', admin_update_settings.timezone;
  end if;
  if admin_update_settings.assistant_provider is not null and admin_update_settings.assistant_provider not in ('claude', 'grok') then
    raise exception 'assistant_provider must be claude or grok';
  end if;
  update public.platform_settings s
     set display_name       = coalesce(nullif(btrim(admin_update_settings.display_name), ''), s.display_name),
         timezone           = coalesce(admin_update_settings.timezone, s.timezone),
         briefs_keep_days   = coalesce(admin_update_settings.briefs_keep_days, s.briefs_keep_days),
         quotes_keep_days   = coalesce(admin_update_settings.quotes_keep_days, s.quotes_keep_days),
         news_keep_reports  = coalesce(admin_update_settings.news_keep_reports, s.news_keep_reports),
         assistant_provider = coalesce(admin_update_settings.assistant_provider, s.assistant_provider),
         metrics_keep_days  = coalesce(admin_update_settings.metrics_keep_days, s.metrics_keep_days),
         events_keep_days   = coalesce(admin_update_settings.events_keep_days, s.events_keep_days),
         updated_at         = now(),
         updated_by         = auth.uid()
   where s.id
  returning to_jsonb(s) - 'id' into result;
  perform public.log_admin_action('update_settings', 'settings', null, changes);
  return result;
end $$;

-- ───────────────────────── Row-level security ─────────────────────────

alter table public.projects        enable row level security;
alter table public.project_updates enable row level security;
alter table public.metrics         enable row level security;
alter table public.metric_settings enable row level security;
alter table public.dashboards      enable row level security;
alter table public.events          enable row level security;

create policy projects_read        on public.projects        for select using (public.can_read());
create policy project_updates_read on public.project_updates for select using (public.can_read());
create policy metrics_read         on public.metrics         for select using (public.can_read());
create policy metric_settings_read on public.metric_settings for select using (public.can_read());
create policy dashboards_read      on public.dashboards      for select using (public.can_read());
create policy events_read          on public.events          for select using (public.can_read());

revoke execute on function public.ingest_projects(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.ingest_metrics(uuid, jsonb, timestamptz) from public, anon, authenticated;
revoke execute on function public.ingest_dashboards(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.ingest_events(uuid, jsonb, text) from public, anon, authenticated;
revoke execute on function public.prune_productivity() from public, anon, authenticated;
revoke execute on all functions in schema public from public, anon;
grant execute on function public.is_platform_admin() to anon;
grant execute on function public.is_device() to anon;
grant execute on function public.can_read() to anon;
