-- Grok bots: agents McFly runs itself. Grok's own scheduled tasks can't send
-- an HTTP request, so instead of each bot pushing, McFly keeps the bot's
-- prompt and schedule, asks Grok through xAI's API (with web and X search)
-- when it's due, and stores the answer as a brief or a Daily Pulse report,
-- under the bot's own agent. Everything downstream (display, web, apps,
-- assistant) sees it like any agent's push.
--
-- The schedule: every_minutes (15..1440), optionally anchored to a time of
-- day in the display's time zone (at_minute: the first run of the day). The
-- `bots` edge function runs what's due; pg_cron calls it every 5 minutes
-- (the guarded block at the end, like 20261015000003).

create table if not exists public.bots (
  id             uuid primary key default gen_random_uuid(),
  agent_id       uuid not null unique references public.agents on delete cascade,
  prompt         text not null check (length(btrim(prompt)) between 10 and 8000),
  output         text not null default 'brief' check (output in ('brief', 'news')),
  every_minutes  int not null default 60 check (every_minutes between 15 and 1440),
  at_minute      int check (at_minute between 0 and 1439),
  web_search     boolean not null default true,
  x_search       boolean not null default true,
  model          text not null default '' check (length(model) <= 60),  -- '' = the function's default
  enabled        boolean not null default true,
  next_run_at    timestamptz not null default now(),
  last_run_at    timestamptz,
  last_status    text check (last_status in ('ok', 'error')),
  last_error     text,
  running_since  timestamptz,  -- a claim, so two invocations never run one bot twice
  created_at     timestamptz not null default now()
);
alter table public.bots enable row level security;
revoke all on public.bots from anon, authenticated;

create table if not exists public.bot_runs (
  id           bigint generated always as identity primary key,
  bot_id       uuid not null references public.bots on delete cascade,
  started_at   timestamptz not null default now(),
  finished_at  timestamptz,
  status       text not null default 'running' check (status in ('running', 'ok', 'error')),
  title        text,
  error        text,
  sources      int not null default 0,
  model        text
);
create index if not exists bot_runs_recent on public.bot_runs (bot_id, id desc);
alter table public.bot_runs enable row level security;
revoke all on public.bot_runs from anon, authenticated;

-- When a bot next runs after `from_time`: every N minutes, or, anchored,
-- the day's runs start at at_minute (display time zone) and repeat every N
-- minutes until midnight, then start again at at_minute the next day.
create or replace function public.bot_next_run(every_minutes int, at_minute int, from_time timestamptz)
returns timestamptz
language plpgsql stable set search_path = public as $$
declare
  tz text := coalesce((select nullif(timezone, '') from public.platform_settings limit 1), 'UTC');
  local_now timestamp;
  d date;
  m int;
begin
  if at_minute is null then
    return from_time + make_interval(mins => every_minutes);
  end if;
  begin
    local_now := from_time at time zone tz;
  exception when others then
    tz := 'UTC';
    local_now := from_time at time zone tz;
  end;
  for i in 0..2 loop
    d := local_now::date + i;
    m := at_minute;
    while m < 1440 loop
      if d + make_interval(mins => m) > local_now then
        return (d + make_interval(mins => m)) at time zone tz;
      end if;
      m := m + every_minutes;
    end loop;
  end loop;
  return from_time + make_interval(mins => every_minutes);
end $$;

create function public.admin_list_bots()
returns table (id uuid, agent_id uuid, name text, color text, scopes text[], prompt text, output text, every_minutes int,
               at_minute int, web_search boolean, x_search boolean, model text, enabled boolean, next_run_at timestamptz,
               last_run_at timestamptz, last_status text, last_error text, runs_7d int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query
    select b.id, a.id, a.name, a.color, a.scopes, b.prompt, b.output, b.every_minutes, b.at_minute, b.web_search, b.x_search,
           b.model, b.enabled, b.next_run_at, b.last_run_at, b.last_status, b.last_error,
           (select count(*)::int from public.bot_runs r where r.bot_id = b.id and r.started_at >= now() - interval '7 days')
    from public.bots b join public.agents a on a.id = b.agent_id
    order by b.created_at, b.id;
end $$;

create function public.admin_list_bot_runs(bot uuid, lim int default 20)
returns table (id bigint, started_at timestamptz, finished_at timestamptz, status text, title text, error text, sources int, model text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query
    select r.id, r.started_at, r.finished_at, r.status, r.title, r.error, r.sources, r.model
    from public.bot_runs r where r.bot_id = bot order by r.id desc limit least(greatest(coalesce(lim, 20), 1), 100);
end $$;

-- Creates a bot (id null: with its agent) or changes one. Fields left null
-- keep their values.
create function public.admin_save_bot(id uuid default null, name text default null, color text default null,
                                      prompt text default null, output text default null, every_minutes int default null,
                                      at_minute int default null, clear_at_minute boolean default false,
                                      web_search boolean default null, x_search boolean default null,
                                      model text default null, enabled boolean default null, scopes text[] default null)
returns uuid
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  saved uuid;
  agent uuid;
  b public.bots;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  if admin_save_bot.id is null then
    if admin_save_bot.prompt is null or length(btrim(admin_save_bot.prompt)) < 10 then raise exception 'write what the bot should do (at least a sentence)'; end if;
    if (select count(*) from public.bots) >= 25 then raise exception 'at most 25 bots'; end if;
    select x.id into agent from public.admin_create_agent(coalesce(nullif(btrim(admin_save_bot.name), ''), 'Grok bot'), 'grok', admin_save_bot.color) x;
    -- A bot is run by McFly, not by a key holder: no key.
    delete from public.agent_keys k where k.agent_id = agent;
    insert into public.bots (agent_id, prompt, output, every_minutes, at_minute, web_search, x_search, model, enabled)
    values (agent, btrim(admin_save_bot.prompt), coalesce(admin_save_bot.output, 'brief'), coalesce(admin_save_bot.every_minutes, 60),
            case when clear_at_minute then null else admin_save_bot.at_minute end,
            coalesce(admin_save_bot.web_search, true), coalesce(admin_save_bot.x_search, true),
            coalesce(btrim(admin_save_bot.model), ''), coalesce(admin_save_bot.enabled, true))
    returning bots.id into saved;
    update public.bots x set next_run_at = case when x.at_minute is null then now() else public.bot_next_run(x.every_minutes, x.at_minute, now()) end
     where x.id = saved;
  else
    select * into b from public.bots x where x.id = admin_save_bot.id;
    if not found then raise exception 'bot not found'; end if;
    agent := b.agent_id;
    if admin_save_bot.prompt is not null and length(btrim(admin_save_bot.prompt)) < 10 then raise exception 'write what the bot should do (at least a sentence)'; end if;
    update public.bots x
       set prompt = coalesce(btrim(admin_save_bot.prompt), x.prompt),
           output = coalesce(admin_save_bot.output, x.output),
           every_minutes = coalesce(admin_save_bot.every_minutes, x.every_minutes),
           at_minute = case when clear_at_minute then null else coalesce(admin_save_bot.at_minute, x.at_minute) end,
           web_search = coalesce(admin_save_bot.web_search, x.web_search),
           x_search = coalesce(admin_save_bot.x_search, x.x_search),
           model = coalesce(btrim(admin_save_bot.model), x.model),
           enabled = coalesce(admin_save_bot.enabled, x.enabled)
     where x.id = admin_save_bot.id
     returning x.id into saved;
    update public.bots x set next_run_at = public.bot_next_run(x.every_minutes, x.at_minute, coalesce(x.last_run_at, now() - make_interval(mins => x.every_minutes)))
     where x.id = saved and (admin_save_bot.every_minutes is not null or admin_save_bot.at_minute is not null or clear_at_minute);
    if admin_save_bot.name is not null or admin_save_bot.color is not null then
      perform public.admin_update_agent(agent, admin_save_bot.name, null, admin_save_bot.color);
    end if;
  end if;
  if admin_save_bot.scopes is not null then
    perform public.admin_set_agent_scopes(agent, admin_save_bot.scopes);
  end if;
  perform public.log_admin_action('save_bot', 'bot', saved::text,
                                  jsonb_strip_nulls(jsonb_build_object('enabled', admin_save_bot.enabled, 'every_minutes', admin_save_bot.every_minutes,
                                                                       'output', admin_save_bot.output)));
  return saved;
end $$;

-- Deleting the bot's agent takes the bot, its runs and everything it wrote.
create function public.admin_delete_bot(bot uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  agent uuid;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  select b.agent_id into agent from public.bots b where b.id = bot;
  if agent is null then raise exception 'bot not found'; end if;
  perform public.admin_delete_agent(agent);
end $$;

-- For the bots function (service role). Claims up to `lim` due bots (or the
-- one asked for), so overlapping invocations don't run one twice; a claim
-- older than 10 minutes is considered dead.
create function public.bots_claim(lim int default 2, bot uuid default null)
returns table (id uuid, agent_id uuid, name text, scopes text[], prompt text, output text, web_search boolean, x_search boolean,
               model text, run_id bigint)
language plpgsql security definer set search_path = public as $$
declare
  b record;
  run bigint;
begin
  if not public.is_platform_admin() then raise exception 'service only'; end if;
  for b in
    select x.* from public.bots x
    where (case when bots_claim.bot is null then x.enabled and x.next_run_at <= now() else x.id = bots_claim.bot end)
      and (x.running_since is null or x.running_since < now() - interval '10 minutes')
    order by x.next_run_at
    limit least(greatest(coalesce(lim, 2), 1), 5)
    for update skip locked
  loop
    update public.bots x set running_since = now() where x.id = b.id;
    insert into public.bot_runs (bot_id) values (b.id) returning bot_runs.id into run;
    return query
      select b.id, a.id, a.name, a.scopes, b.prompt, b.output, b.web_search, b.x_search, b.model, run
      from public.agents a where a.id = b.agent_id;
  end loop;
end $$;

create function public.bot_run_finished(run bigint, status text, title text default null, error text default null,
                                        sources int default 0, model text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  b uuid;
begin
  if not public.is_platform_admin() then raise exception 'service only'; end if;
  update public.bot_runs r
     set finished_at = now(), status = bot_run_finished.status, title = left(bot_run_finished.title, 300),
         error = left(bot_run_finished.error, 500), sources = coalesce(bot_run_finished.sources, 0), model = left(bot_run_finished.model, 60)
   where r.id = run returning r.bot_id into b;
  update public.bots x
     set running_since = null, last_run_at = now(), last_status = bot_run_finished.status,
         last_error = case when bot_run_finished.status = 'error' then left(bot_run_finished.error, 500) end,
         next_run_at = public.bot_next_run(x.every_minutes, x.at_minute, now())
   where x.id = b;
  -- Keep the last 50 runs per bot.
  delete from public.bot_runs r where r.bot_id = b and r.id <= coalesce(
    (select r2.id from public.bot_runs r2 where r2.bot_id = b order by r2.id desc offset 50 limit 1), 0);
end $$;

-- The background a bot gets: the display's name and zone, and what its
-- scopes allow (shared notes, upcoming events). Data, not instructions.
create function public.bot_context(agent uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'display_name', (select display_name from public.platform_settings limit 1),
    'timezone', (select timezone from public.platform_settings limit 1),
    'memories', case when (select 'memory:read' = any (a.scopes) from public.agents a where a.id = agent)
                     then (select coalesce(jsonb_agg(m.text order by m.pinned desc, m.updated_at desc), '[]')
                           from (select * from public.memories m where m.agent_id is null or m.agent_id = agent
                                 order by m.pinned desc, m.updated_at desc limit 40) m)
                     else '[]' end,
    'events', case when (select 'calendar:read' = any (a.scopes) from public.agents a where a.id = agent)
                   then (select coalesce(jsonb_agg(jsonb_build_object('title', e.title, 'starts_at', e.starts_at, 'ends_at', e.ends_at,
                                                                      'all_day', e.all_day, 'location', e.location) order by e.starts_at), '[]')
                         from (select * from public.events e where e.ends_at >= now() and e.starts_at < now() + interval '3 days'
                               order by e.starts_at limit 60) e)
                   else '[]' end)
  where public.is_platform_admin()
$$;

revoke execute on function public.bot_next_run(int, int, timestamptz) from public, anon, authenticated;
revoke execute on function public.bots_claim(int, uuid) from public, anon, authenticated;
revoke execute on function public.bot_run_finished(bigint, text, text, text, int, text) from public, anon, authenticated;
revoke execute on function public.bot_context(uuid) from public, anon, authenticated;
revoke execute on function public.admin_list_bots() from public, anon;
revoke execute on function public.admin_list_bot_runs(uuid, int) from public, anon;
revoke execute on function public.admin_save_bot(uuid, text, text, text, text, int, int, boolean, boolean, boolean, text, boolean, text[]) from public, anon;
revoke execute on function public.admin_delete_bot(uuid) from public, anon;
grant execute on function public.admin_list_bots() to authenticated;
grant execute on function public.admin_list_bot_runs(uuid, int) to authenticated;
grant execute on function public.admin_save_bot(uuid, text, text, text, text, int, int, boolean, boolean, boolean, text, boolean, text[]) to authenticated;
grant execute on function public.admin_delete_bot(uuid) to authenticated;

-- The schedule: every 5 minutes, the bots function runs what's due. Same
-- Vault values as the calendar sync; does nothing until they're set.
create or replace function public.bots_tick()
returns void
language plpgsql security definer set search_path = public as $$
declare
  base text;
  secret text;
begin
  if to_regnamespace('vault') is null or to_regnamespace('net') is null then
    return;
  end if;
  if not exists (select 1 from public.bots where enabled and next_run_at <= now()) then
    return;
  end if;
  execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'mcfly_project_url'$q$ into base;
  execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'mcfly_cron_secret'$q$ into secret;
  if base is null or secret is null then
    return;
  end if;
  execute $q$select net.http_post(url := $1, headers := $2, body := '{}'::jsonb, timeout_milliseconds := 150000)$q$
    using rtrim(base, '/') || '/functions/v1/bots',
          jsonb_build_object('Content-Type', 'application/json', 'x-mcfly-cron', secret);
end $$;
revoke execute on function public.bots_tick() from public, anon, authenticated;

do $$
begin
  if to_regnamespace('cron') is not null then
    perform cron.unschedule(jobid) from cron.job where jobname = 'mcfly-bots';
    perform cron.schedule('mcfly-bots', '*/5 * * * *', 'select public.bots_tick()');
  end if;
end $$;
