-- Calendar subscriptions: an iCal link (Google's "secret address in iCal
-- format", an iCloud public calendar, an Outlook ICS link) that McFly reads
-- every 15 minutes and writes into `events` like any agent's push, so the
-- display, the web and the apps show it with nothing new to learn.
--
-- The link is a secret (anyone with it reads the calendar): it lives in this
-- table, which has no policies, and only the calendar-sync edge function
-- (service role) reads it. The console sees its host only.
--
-- The events belong to one built-in agent, "Calendar subscriptions", with
-- each source as its own calendar name, written through ingest_events with
-- replace so moved and cancelled events follow. The schedule itself (pg_cron
-- and pg_net) is in 20261015000003, which only Supabase can run.

create table if not exists public.calendar_sources (
  id              uuid primary key default gen_random_uuid(),
  name            text not null unique check (length(btrim(name)) between 1 and 80),
  url             text not null check (url ~* '^(https?|webcal)://' and length(url) <= 2000),
  color           text check (color is null or color ~* '^#[0-9a-f]{6}$'),
  enabled         boolean not null default true,
  last_synced_at  timestamptz,
  last_error      text,
  event_count     int not null default 0,
  created_at      timestamptz not null default now()
);
alter table public.calendar_sources enable row level security;
revoke all on public.calendar_sources from anon, authenticated;

-- The agent that owns subscribed events. Made on first use; it has no key,
-- so nothing can push as it.
create or replace function public.calendar_sources_agent()
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  agent uuid;
begin
  select a.id into agent from public.agents a where a.slug = 'calendar-subscriptions';
  if agent is null then
    insert into public.agents (name, slug, kind, color)
    values ('Calendar subscriptions', 'calendar-subscriptions', 'other', '#14C2C2')
    on conflict (slug) do nothing
    returning id into agent;
    if agent is null then
      select a.id into agent from public.agents a where a.slug = 'calendar-subscriptions';
    end if;
  end if;
  return agent;
end $$;

-- What the console shows: never the link, only where it points.
create or replace function public.calendar_source_host(url text)
returns text
language sql immutable set search_path = public as $$
  select coalesce(substring(url from '^[a-zA-Z]+://([^/?#]+)'), 'link')
$$;

create function public.admin_list_calendar_sources()
returns table (id uuid, name text, host text, color text, enabled boolean, last_synced_at timestamptz,
               last_error text, event_count int, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query
    select s.id, s.name, public.calendar_source_host(s.url), s.color, s.enabled, s.last_synced_at, s.last_error,
           s.event_count, s.created_at
    from public.calendar_sources s order by s.created_at, s.id;
end $$;

create function public.admin_add_calendar_source(name text, url text, color text default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  added uuid;
  link text := btrim(admin_add_calendar_source.url);
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  if link ~* '^webcal://' then link := 'https://' || substring(link from 10); end if;
  if link !~* '^https?://[^/]+' then raise exception 'paste the calendar''s iCal link (it starts with https:// or webcal://)'; end if;
  if (select count(*) from public.calendar_sources) >= 20 then raise exception 'at most 20 calendars'; end if;
  insert into public.calendar_sources (name, url, color)
  values (btrim(admin_add_calendar_source.name), link, nullif(btrim(admin_add_calendar_source.color), ''))
  returning id into added;
  perform public.calendar_sources_agent();
  perform public.log_admin_action('add_calendar_source', 'calendar_source', added::text,
                                  jsonb_build_object('name', btrim(admin_add_calendar_source.name), 'host', public.calendar_source_host(link)));
  return added;
exception when unique_violation then
  raise exception 'there is already a calendar called %', btrim(admin_add_calendar_source.name);
end $$;

-- Rename, recolor, pause or resume. A rename carries its events along, so
-- the next sync replaces them instead of leaving a copy under the old name.
create function public.admin_update_calendar_source(source uuid, name text default null, color text default null,
                                                    enabled boolean default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  old public.calendar_sources;
  new_name text := nullif(btrim(admin_update_calendar_source.name), '');
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  select * into old from public.calendar_sources s where s.id = source;
  if not found then raise exception 'calendar not found'; end if;
  update public.calendar_sources s
     set name = coalesce(new_name, s.name),
         color = case when admin_update_calendar_source.color is null then s.color
                      else nullif(btrim(admin_update_calendar_source.color), '') end,
         enabled = coalesce(admin_update_calendar_source.enabled, s.enabled)
   where s.id = source;
  if new_name is not null and new_name <> old.name then
    update public.events e set calendar = new_name
     where e.agent_id = public.calendar_sources_agent() and e.calendar = old.name;
  end if;
  if admin_update_calendar_source.color is not null then
    update public.events e set color = nullif(btrim(admin_update_calendar_source.color), '')
     where e.agent_id = public.calendar_sources_agent() and e.calendar = coalesce(new_name, old.name);
  end if;
  perform public.log_admin_action('update_calendar_source', 'calendar_source', source::text,
                                  jsonb_strip_nulls(jsonb_build_object('name', new_name, 'color', admin_update_calendar_source.color,
                                                                       'enabled', admin_update_calendar_source.enabled)));
exception when unique_violation then
  raise exception 'there is already a calendar called %', new_name;
end $$;

-- Removes the subscription and the events it brought.
create function public.admin_delete_calendar_source(source uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  old public.calendar_sources;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  delete from public.calendar_sources s where s.id = source returning * into old;
  if old.id is null then raise exception 'calendar not found'; end if;
  delete from public.events e where e.agent_id = public.calendar_sources_agent() and e.calendar = old.name;
  perform public.log_admin_action('delete_calendar_source', 'calendar_source', source::text, jsonb_build_object('name', old.name));
end $$;

-- For the display and the apps: each subscription's name and health.
create function public.list_calendar_sources()
returns table (name text, color text, enabled boolean, last_synced_at timestamptz, last_error text, event_count int)
language sql stable security definer set search_path = public as $$
  select s.name, s.color, s.enabled, s.last_synced_at, s.last_error, s.event_count
  from public.calendar_sources s
  where public.can_read()
  order by s.created_at, s.id
$$;

-- For the calendar-sync function (service role): what to read, and where
-- each read landed. `source` limits a run to one source ("Sync now").
create function public.calendar_sources_due(source uuid default null)
returns table (id uuid, name text, url text, color text, agent uuid)
language sql security definer set search_path = public as $$
  select s.id, s.name, s.url, s.color, public.calendar_sources_agent()
  from public.calendar_sources s
  where public.is_platform_admin() and s.enabled and (calendar_sources_due.source is null or s.id = calendar_sources_due.source)
  order by s.last_synced_at nulls first
  limit 20
$$;

create function public.calendar_source_synced(source uuid, count int, error text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'service only'; end if;
  update public.calendar_sources s
     set last_synced_at = case when error is null then now() else s.last_synced_at end,
         last_error = left(error, 300),
         event_count = case when error is null then coalesce(count, 0) else s.event_count end
   where s.id = source;
end $$;

revoke execute on function public.calendar_sources_agent() from public, anon, authenticated;
revoke execute on function public.calendar_source_host(text) from public, anon, authenticated;
revoke execute on function public.calendar_sources_due(uuid) from public, anon, authenticated;
revoke execute on function public.calendar_source_synced(uuid, int, text) from public, anon, authenticated;
revoke execute on function public.admin_list_calendar_sources() from public, anon;
revoke execute on function public.admin_add_calendar_source(text, text, text) from public, anon;
revoke execute on function public.admin_update_calendar_source(uuid, text, text, boolean) from public, anon;
revoke execute on function public.admin_delete_calendar_source(uuid) from public, anon;
revoke execute on function public.list_calendar_sources() from public, anon;
grant execute on function public.admin_list_calendar_sources() to authenticated;
grant execute on function public.admin_add_calendar_source(text, text, text) to authenticated;
grant execute on function public.admin_update_calendar_source(uuid, text, text, boolean) to authenticated;
grant execute on function public.admin_delete_calendar_source(uuid) to authenticated;
grant execute on function public.list_calendar_sources() to authenticated;
