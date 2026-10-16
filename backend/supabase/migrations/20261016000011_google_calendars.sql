-- Google Calendar by sign-in. Instead of pasting a calendar's secret iCal
-- address (which Google hides for shared and many Workspace calendars, and
-- serves hours stale), the admin signs in to Google once (OAuth, read-only)
-- and picks calendars from the account's list. calendar-sync then reads them
-- through the Calendar API: every calendar the account can see, recurring
-- events expanded by Google, the calendar as it is now.
--
-- The refresh token is the secret: it lives in google_accounts, a table with
-- no policies that only the functions (service role) read; the console sees
-- the account's email and health. A picked calendar is a calendar_sources
-- row of kind 'google' (the account and Google's calendar id instead of a
-- link), so everything downstream (the built-in agent, replace-whole syncs,
-- rename, pause, the display's list) is as for a link.
-- Migration 20261015000002 has the links; the google-calendar function does
-- the sign-in.

create table public.google_accounts (
  id             uuid primary key default gen_random_uuid(),
  email          text not null unique check (length(email) between 3 and 320),
  refresh_token  text not null,
  scope          text,
  connected_by   uuid,
  connected_at   timestamptz not null default now(),
  last_error     text,
  created_at     timestamptz not null default now()
);
alter table public.google_accounts enable row level security;
revoke all on public.google_accounts from anon, authenticated;

-- A sign-in under way: the random state the console's browser carries to
-- Google and back, who began it, and where to send them afterwards. One use,
-- ten minutes. Service role only.
create table public.google_oauth_states (
  state       text primary key check (length(state) between 32 and 128),
  user_id     uuid not null,
  return_to   text not null check (return_to ~* '^https?://' and length(return_to) <= 2000),
  created_at  timestamptz not null default now()
);
alter table public.google_oauth_states enable row level security;
revoke all on public.google_oauth_states from anon, authenticated;

-- A subscription is a link or a Google calendar.
alter table public.calendar_sources
  add column kind text not null default 'ical' check (kind in ('ical', 'google')),
  add column google_account_id uuid references public.google_accounts on delete cascade,
  add column google_calendar_id text check (length(google_calendar_id) between 1 and 300),
  alter column url drop not null;
alter table public.calendar_sources drop constraint calendar_sources_url_check;
alter table public.calendar_sources
  add constraint calendar_sources_url_check
    check (url is null or (url ~* '^(https?|webcal)://' and length(url) <= 2000)),
  add constraint calendar_sources_kind_fields
    check ((kind = 'ical' and url is not null and google_account_id is null and google_calendar_id is null)
        or (kind = 'google' and url is null and google_account_id is not null and google_calendar_id is not null));
create unique index calendar_sources_google_calendar on public.calendar_sources (google_account_id, google_calendar_id);

-- ───────────────────────────── Console ─────────────────────────────

-- The list grows the kind and, for a Google calendar, its account. A link
-- still shows its host only; a Google calendar shows the account's email.
drop function public.admin_list_calendar_sources();
create function public.admin_list_calendar_sources()
returns table (id uuid, name text, host text, color text, enabled boolean, last_synced_at timestamptz,
               last_error text, event_count int, created_at timestamptz,
               kind text, account_id uuid, account_email text, google_calendar_id text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query
    select s.id, s.name,
           case when s.kind = 'google' then 'calendar.google.com' else public.calendar_source_host(s.url) end,
           s.color, s.enabled, s.last_synced_at, s.last_error, s.event_count, s.created_at,
           s.kind, s.google_account_id, g.email, s.google_calendar_id
    from public.calendar_sources s
    left join public.google_accounts g on g.id = s.google_account_id
    order by s.created_at, s.id;
end $$;

create function public.admin_list_google_accounts()
returns table (id uuid, email text, connected_at timestamptz, last_error text, calendars int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query
    select g.id, g.email, g.connected_at, g.last_error,
           (select count(*)::int from public.calendar_sources s where s.google_account_id = g.id)
    from public.google_accounts g
    order by g.created_at, g.id;
end $$;

-- Picks one of a connected account's calendars. The name is Google's for it
-- (the console passes it along), with the account's email appended when
-- another calendar already has that name.
create function public.admin_add_google_calendar(account uuid, calendar_id text, name text, color text default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  added uuid;
  acct public.google_accounts;
  wanted text := left(btrim(coalesce(admin_add_google_calendar.name, '')), 80);
  cal text := btrim(coalesce(admin_add_google_calendar.calendar_id, ''));
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  select * into acct from public.google_accounts g where g.id = admin_add_google_calendar.account;
  if not found then raise exception 'that Google account isn''t connected'; end if;
  if cal = '' or length(cal) > 300 then raise exception 'which calendar?'; end if;
  if wanted = '' then wanted := 'Google'; end if;
  if exists (select 1 from public.calendar_sources s where s.google_account_id = acct.id and s.google_calendar_id = cal) then
    raise exception 'that calendar is already added';
  end if;
  if (select count(*) from public.calendar_sources) >= 20 then raise exception 'at most 20 calendars'; end if;
  if exists (select 1 from public.calendar_sources s where s.name = wanted) then
    wanted := left(wanted || ' (' || acct.email || ')', 80);
  end if;
  insert into public.calendar_sources (name, kind, google_account_id, google_calendar_id, color)
  values (wanted, 'google', acct.id, cal, nullif(btrim(admin_add_google_calendar.color), ''))
  returning id into added;
  perform public.calendar_sources_agent();
  perform public.log_admin_action('add_calendar_source', 'calendar_source', added::text,
                                  jsonb_build_object('name', wanted, 'kind', 'google', 'account', acct.email));
  return added;
exception when unique_violation then
  raise exception 'there is already a calendar called %', wanted;
end $$;

-- Removes the account, its calendars and the events they brought. The
-- google-calendar function revokes the token at Google first, then calls
-- this as the admin so the audit row is theirs. Returns the email.
create function public.admin_delete_google_account(account uuid)
returns text
language plpgsql security definer set search_path = public as $$
declare
  acct public.google_accounts;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  select * into acct from public.google_accounts g where g.id = admin_delete_google_account.account;
  if not found then raise exception 'that Google account isn''t connected'; end if;
  delete from public.events e
   where e.agent_id = public.calendar_sources_agent()
     and e.calendar in (select s.name from public.calendar_sources s where s.google_account_id = acct.id);
  delete from public.google_accounts g where g.id = acct.id;
  perform public.log_admin_action('disconnect_google_account', 'google_account', acct.id::text,
                                  jsonb_build_object('email', acct.email));
  return acct.email;
end $$;

-- ───────────────────────────── The functions (service role) ─────────────────────────────

create function public.google_oauth_begin(state text, who uuid, return_to text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'service only'; end if;
  if who is null then raise exception 'who began the sign-in?'; end if;
  delete from public.google_oauth_states s where s.created_at < now() - interval '15 minutes';
  insert into public.google_oauth_states (state, user_id, return_to)
  values (google_oauth_begin.state, who, btrim(google_oauth_begin.return_to));
end $$;

-- Spends the state: the row is removed, and comes back only if it is
-- under ten minutes old.
create function public.google_oauth_finish(state text)
returns table (user_id uuid, return_to text)
language plpgsql security definer set search_path = public as $$
declare
  st public.google_oauth_states;
begin
  if not public.is_platform_admin() then raise exception 'service only'; end if;
  delete from public.google_oauth_states s where s.state = google_oauth_finish.state returning * into st;
  if st.state is null or st.created_at < now() - interval '10 minutes' then return; end if;
  user_id := st.user_id;
  return_to := st.return_to;
  return next;
end $$;

-- Keeps the sign-in. Connecting the same account again replaces its token
-- and keeps its calendars. The audit row names the admin who began it.
create function public.google_account_save(email text, refresh_token text, scope text, who uuid)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  saved uuid;
  addr text := lower(btrim(coalesce(google_account_save.email, '')));
begin
  if not public.is_platform_admin() then raise exception 'service only'; end if;
  if addr !~ '^[^@\s]+@[^@\s]+$' then raise exception 'not an email address'; end if;
  if coalesce(google_account_save.refresh_token, '') = '' then raise exception 'no refresh token'; end if;
  if (select count(*) from public.google_accounts) >= 10 and not exists (select 1 from public.google_accounts g where g.email = addr) then
    raise exception 'at most 10 Google accounts';
  end if;
  insert into public.google_accounts as g (email, refresh_token, scope, connected_by)
  values (addr, google_account_save.refresh_token, google_account_save.scope, who)
  on conflict on constraint google_accounts_email_key do update
    set refresh_token = excluded.refresh_token, scope = excluded.scope, connected_by = excluded.connected_by,
        connected_at = now(), last_error = null
  returning g.id into saved;
  insert into public.admin_audit_log (admin_id, action, target_type, target_id, details)
  values (who, 'connect_google_account', 'google_account', saved::text, jsonb_build_object('email', addr));
  return saved;
end $$;

create function public.google_account_credentials(account uuid)
returns table (email text, refresh_token text)
language sql security definer set search_path = public as $$
  select g.email, g.refresh_token
  from public.google_accounts g
  where public.is_platform_admin() and g.id = account
$$;

-- What the console shows under the account ("Google no longer accepts this
-- sign-in; connect it again"); null clears it.
create function public.google_account_failed(account uuid, error text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'service only'; end if;
  update public.google_accounts g set last_error = left(error, 300) where g.id = account;
end $$;

-- The sync list carries each Google calendar's account and token.
drop function public.calendar_sources_due(uuid);
create function public.calendar_sources_due(source uuid default null)
returns table (id uuid, name text, url text, color text, agent uuid, kind text, google_calendar_id text,
               account_id uuid, account_email text, refresh_token text)
language sql security definer set search_path = public as $$
  select s.id, s.name, s.url, s.color, public.calendar_sources_agent(), s.kind, s.google_calendar_id,
         g.id, g.email, g.refresh_token
  from public.calendar_sources s
  left join public.google_accounts g on g.id = s.google_account_id
  where public.is_platform_admin() and s.enabled and (calendar_sources_due.source is null or s.id = calendar_sources_due.source)
  order by s.last_synced_at nulls first
  limit 20
$$;

revoke execute on function public.google_oauth_begin(text, uuid, text) from public, anon, authenticated;
revoke execute on function public.google_oauth_finish(text) from public, anon, authenticated;
revoke execute on function public.google_account_save(text, text, text, uuid) from public, anon, authenticated;
revoke execute on function public.google_account_credentials(uuid) from public, anon, authenticated;
revoke execute on function public.google_account_failed(uuid, text) from public, anon, authenticated;
revoke execute on function public.calendar_sources_due(uuid) from public, anon, authenticated;
revoke execute on function public.admin_list_calendar_sources() from public, anon;
revoke execute on function public.admin_list_google_accounts() from public, anon;
revoke execute on function public.admin_add_google_calendar(uuid, text, text, text) from public, anon;
revoke execute on function public.admin_delete_google_account(uuid) from public, anon;
grant execute on function public.admin_list_calendar_sources() to authenticated;
grant execute on function public.admin_list_google_accounts() to authenticated;
grant execute on function public.admin_add_google_calendar(uuid, text, text, text) to authenticated;
grant execute on function public.admin_delete_google_account(uuid) to authenticated;
