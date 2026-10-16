-- Google push notifications for the calendars signed in with
-- 20261016000011. For each subscribed Google calendar, calendar-sync opens a
-- notification channel (events.watch) that points at the google-calendar
-- function's /notify route; when Google says the calendar changed, that
-- route reads the one calendar at once, so a change shows on the display
-- within a minute instead of at the next 15-minute run. A channel lives
-- about a week: calendar-sync renews one with under two days left on its
-- next run and stops the old one. The channel's token is what Google echoes
-- back, so the table is service role only, like the sign-ins.

create table public.google_watch_channels (
  source_id    uuid primary key references public.calendar_sources on delete cascade,
  channel_id   text not null unique check (length(channel_id) between 8 and 128),
  resource_id  text not null check (length(resource_id) between 1 and 200),
  token        text not null check (length(token) between 32 and 128),
  expires_at   timestamptz not null,
  created_at   timestamptz not null default now()
);
alter table public.google_watch_channels enable row level security;
revoke all on public.google_watch_channels from anon, authenticated;

-- Why Google refused a channel ("push.webhookUrlUnauthorized": the address's
-- domain isn't verified), for the console to show beside the calendar.
alter table public.calendar_sources add column watch_error text;

-- The console's list says until when each Google calendar is watched.
drop function public.admin_list_calendar_sources();
create function public.admin_list_calendar_sources()
returns table (id uuid, name text, host text, color text, enabled boolean, last_synced_at timestamptz,
               last_error text, event_count int, created_at timestamptz,
               kind text, account_id uuid, account_email text, google_calendar_id text,
               watch_expires_at timestamptz, watch_error text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query
    select s.id, s.name,
           case when s.kind = 'google' then 'calendar.google.com' else public.calendar_source_host(s.url) end,
           s.color, s.enabled, s.last_synced_at, s.last_error, s.event_count, s.created_at,
           s.kind, s.google_account_id, g.email, s.google_calendar_id,
           w.expires_at, s.watch_error
    from public.calendar_sources s
    left join public.google_accounts g on g.id = s.google_account_id
    left join public.google_watch_channels w on w.source_id = s.id
    order by s.created_at, s.id;
end $$;

-- ───────────────────────────── The functions (service role) ─────────────────────────────

-- Every channel, for a calendar-sync run to see which need renewing.
create function public.google_watch_list()
returns table (source_id uuid, channel_id text, resource_id text, expires_at timestamptz)
language sql security definer set search_path = public as $$
  select w.source_id, w.channel_id, w.resource_id, w.expires_at
  from public.google_watch_channels w
  where public.is_platform_admin()
$$;

-- A channel Google made (or renewed) for a calendar; clears any refusal.
create function public.google_watch_save(source uuid, channel_id text, resource_id text, token text, expires_at timestamptz)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'service only'; end if;
  if not exists (select 1 from public.calendar_sources s where s.id = source and s.kind = 'google') then
    raise exception 'not a Google calendar';
  end if;
  insert into public.google_watch_channels as w (source_id, channel_id, resource_id, token, expires_at)
  values (source, google_watch_save.channel_id, google_watch_save.resource_id, google_watch_save.token, google_watch_save.expires_at)
  on conflict on constraint google_watch_channels_pkey do update
    set channel_id = excluded.channel_id, resource_id = excluded.resource_id, token = excluded.token,
        expires_at = excluded.expires_at, created_at = now();
  update public.calendar_sources s set watch_error = null where s.id = source;
end $$;

create function public.google_watch_failed(source uuid, error text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'service only'; end if;
  update public.calendar_sources s set watch_error = left(error, 300) where s.id = source;
end $$;

-- A notification's channel: whose calendar, the token to compare, and
-- whether and when it was last read (the route skips a burst).
create function public.google_watch_for_channel(channel text)
returns table (source_id uuid, token text, enabled boolean, last_synced_at timestamptz)
language sql security definer set search_path = public as $$
  select w.source_id, w.token, s.enabled, s.last_synced_at
  from public.google_watch_channels w
  join public.calendar_sources s on s.id = w.source_id
  where public.is_platform_admin() and w.channel_id = channel
$$;

revoke execute on function public.google_watch_list() from public, anon, authenticated;
revoke execute on function public.google_watch_save(uuid, text, text, text, timestamptz) from public, anon, authenticated;
revoke execute on function public.google_watch_failed(uuid, text) from public, anon, authenticated;
revoke execute on function public.google_watch_for_channel(text) from public, anon, authenticated;
revoke execute on function public.admin_list_calendar_sources() from public, anon;
grant execute on function public.admin_list_calendar_sources() to authenticated;
