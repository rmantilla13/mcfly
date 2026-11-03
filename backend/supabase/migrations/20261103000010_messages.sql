-- Messages: the people at home write to the person from a display, and the
-- person writes back from the app or the console. One household thread.
--
-- A display sends through send_message() and marks what it has shown as read
-- through read_messages(), the fifth and sixth things a display may write
-- (after its check-in, its settings, dismiss() and answer_ask()). Who wrote
-- (`sender_kind`, `device_id`, `via`) is the server's to say, never the
-- caller's. A display's message names one of the people listed in
-- platform_settings.message_names, or, with none listed or none picked, the
-- display itself; the person's carries the name the household calls them
-- (profiles.message_name, set with set_message_name()).
--
-- A display's message reaches the person's phones as a notification: a
-- trigger asks the `notify` edge function (with the cron secret, through
-- pg_net, after the commit), which reads it with message_push() and sends it
-- to every registered phone (push_tokens) through Apple's push service. Its
-- outcome comes back as notified_at or notify_error, which the display shows
-- under the message. Without Vault and pg_net (the local test run) nothing
-- is sent; a failure there is a warning, never the sender's error.
--
-- Not an agent feed: no ingest function, nothing in docs/AGENTS.md.
-- Everything here is new; the only changes to older tables are two columns.

alter table public.platform_settings
  -- Who writes from the displays, for the "Who's writing?" buttons: at most
  -- 8 names of 1 to 24 characters, no two alike. Empty: messages carry the
  -- display's name.
  add column message_names text[] not null default '{}';

alter table public.profiles
  -- What the household calls this person ("Dad"), on their replies. Null
  -- until they say: replies are from "Parent" meanwhile.
  add column message_name text check (message_name is null or (length(message_name) between 1 and 24 and message_name !~ '[\x01-\x1f\x7f]'));

create table public.messages (
  id            uuid primary key default gen_random_uuid(),
  -- display: written on a display, by someone at home. person: the person's reply.
  sender_kind   text not null check (sender_kind in ('display', 'person')),
  sender_name   text not null check (length(sender_name) between 1 and 40),
  -- One to 500 characters: lines, but no other control characters.
  body          text not null check (length(body) between 1 and 500 and body !~ '[\x01-\x09\x0b-\x1f\x7f]'),
  -- The display it was written on (set null when the display is revoked).
  device_id     uuid references public.devices on delete set null,
  -- The auth user who sent it: no reference, since a revoked display's goes.
  author        uuid,
  via           text not null check (via in ('display', 'app', 'console')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  -- When the other side read it: the person (a display's message), a display (the person's).
  read_at       timestamptz,
  -- A display's message only: when Apple took it for at least one phone, or why it didn't go.
  notified_at   timestamptz,
  notify_error  text check (length(notify_error) <= 300),
  check ((sender_kind = 'display') = (via = 'display'))
);
create index messages_created_idx on public.messages (created_at desc, id);
-- The screens poll by updated_at, which a read or a notification moves too.
create index messages_updated_idx on public.messages (updated_at);
create index messages_device_idx on public.messages (device_id, created_at) where sender_kind = 'display';
create trigger messages_touch before update on public.messages for each row execute function public.touch_updated_at();

alter table public.messages enable row level security;
create policy messages_read on public.messages for select using (public.can_read());

-- The phones that get a notification for a display's message: one row per
-- app install, as Apple named it. Service role only (RLS on, no policies);
-- written by register_push_token / unregister_push_token. `environment` and
-- `bundle_id` say which of Apple's hosts and which app the token is for: a
-- debug build's token is a sandbox one, and the bundle id is the build's own.
create table public.push_tokens (
  token        text primary key check (token ~ '^[0-9a-f]{64,200}$'),
  user_id      uuid not null references auth.users on delete cascade,
  environment  text not null check (environment in ('sandbox', 'production')),
  bundle_id    text not null check (bundle_id ~ '^[A-Za-z0-9][A-Za-z0-9.-]{0,154}$'),
  platform     text not null default 'ios' check (platform in ('ios', 'macos')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index push_tokens_user_idx on public.push_tokens (user_id);
create trigger push_tokens_touch before update on public.push_tokens for each row execute function public.touch_updated_at();
alter table public.push_tokens enable row level security;

-- ───────────────────────────── Names ─────────────────────────────

-- A name as a button and a bubble show it: trimmed, one line, 1 to 24
-- characters. Raises with `what` when it isn't one.
create function public.message_label(value text, what text)
returns text
language plpgsql immutable set search_path = public as $$
declare
  label text := btrim(coalesce(value, ''));
begin
  if label ~ '[\x01-\x1f\x7f]' then raise exception '% must be one line', what; end if;
  if length(label) not between 1 and 24 then raise exception '% must be 1 to 24 characters', what; end if;
  return label;
end $$;

-- Who writes from the displays (platform_settings.message_names): trimmed,
-- blanks left out, at most 8, no two alike (any case). Returns the list as kept.
create function public.admin_set_message_names(names text[])
returns text[]
language plpgsql security definer set search_path = public as $$
declare
  out text[] := '{}';
  n text;
  label text;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  foreach n in array coalesce(names, '{}') loop
    if btrim(coalesce(n, '')) = '' then continue; end if;
    label := public.message_label(n, 'each name');
    if exists (select 1 from unnest(out) o where lower(o) = lower(label)) then
      raise exception '% is there twice', label;
    end if;
    out := out || label;
  end loop;
  if cardinality(out) > 8 then raise exception 'at most 8 names'; end if;
  update public.platform_settings s set message_names = out, updated_at = now(), updated_by = auth.uid() where s.id;
  perform public.log_admin_action('set_message_names', 'settings', null, jsonb_build_object('names', to_jsonb(out)));
  return out;
end $$;

-- What the household calls the signed-in person, on their replies. Null or
-- blank clears it. Returns the name as kept.
create function public.set_message_name(name text)
returns text
language plpgsql security definer set search_path = public as $$
declare
  label text;
begin
  if not public.is_platform_admin() or public.is_service_role() or auth.uid() is null then
    raise exception 'only the person can name themselves';
  end if;
  if btrim(coalesce(set_message_name.name, '')) <> '' then
    label := public.message_label(set_message_name.name, 'your name');
  end if;
  update public.profiles p set message_name = label where p.id = auth.uid();
  if not found then raise exception 'no profile to name'; end if;
  perform public.log_admin_action('set_message_name', 'profile', auth.uid()::text, jsonb_build_object('name', label));
  return label;
end $$;

-- ───────────────────────────── Sending ─────────────────────────────

-- Send a message to the thread. A paired display sends as one of
-- platform_settings.message_names (`sender_name`, any case; the list's own
-- spelling is kept), or as itself when there's no list or no name; at most
-- 10 a minute and 60 an hour from one display, so a stuck button can't fill
-- a phone. The person (an admin's own sign-in) sends as their message_name,
-- `via` app (the default) or console. The body is trimmed, its line endings
-- made \n, tabs made spaces and runs of blank lines one; 1 to 500 characters
-- must be left. Messages over a year old go. Returns the message as stored.
create function public.send_message(body text, sender_name text default null, via text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  b text;
  kind text;
  who text;
  channel text;
  device uuid;
  device_name text;
  names text[];
  m public.messages;
begin
  if public.is_device() then
    kind := 'display';
    channel := 'display';
    select d.id, d.name into device, device_name from public.devices d where d.user_id = auth.uid();
    select s.message_names into names from public.platform_settings s limit 1;
    if btrim(coalesce(send_message.sender_name, '')) <> '' and cardinality(coalesce(names, '{}')) > 0 then
      select n into who from unnest(names) n where lower(n) = lower(btrim(send_message.sender_name));
      if who is null then
        raise exception 'pick who is writing: %', array_to_string(names, ', ');
      end if;
    end if;
    who := left(coalesce(who, nullif(btrim(device_name), ''), 'Home'), 40);
    if (select count(*) from public.messages x where x.device_id = device and x.created_at > now() - interval '1 minute') >= 10 then
      raise exception 'slow down: wait a minute before sending another message';
    end if;
    if (select count(*) from public.messages x where x.device_id = device and x.created_at > now() - interval '1 hour') >= 60 then
      raise exception 'that''s a lot of messages: wait a while before sending more';
    end if;
  elsif public.is_platform_admin() and not public.is_service_role() and auth.uid() is not null then
    kind := 'person';
    channel := case when send_message.via = 'console' then 'console' else 'app' end;
    select p.message_name into who from public.profiles p where p.id = auth.uid();
    who := coalesce(who, 'Parent');
  else
    raise exception 'only a paired display or an admin can send a message';
  end if;

  b := replace(regexp_replace(coalesce(send_message.body, ''), '\r\n?', E'\n', 'g'), E'\t', ' ');
  b := regexp_replace(b, '[ ]+\n', E'\n', 'g');
  b := btrim(regexp_replace(b, '\n{3,}', E'\n\n', 'g'), E' \n');
  if b ~ '[\x01-\x09\x0b-\x1f\x7f]' then raise exception 'a message can''t hold control characters'; end if;
  if length(b) = 0 then raise exception 'write something to send'; end if;
  if length(b) > 500 then raise exception 'a message can be at most 500 characters'; end if;

  insert into public.messages (sender_kind, sender_name, body, device_id, author, via)
  values (kind, who, b, device, auth.uid(), channel)
  returning * into m;
  delete from public.messages x where x.created_at < now() - interval '365 days';
  return to_jsonb(m);
end $$;

-- Mark the other side's messages read, up to and including `up_to` (a
-- message id; null: all of them): a display reads the person's, the person
-- (an admin's own sign-in) the displays'. Already read ones keep their time.
-- Returns how many were marked.
create function public.read_messages(up_to uuid default null)
returns int
language plpgsql security definer set search_path = public as $$
declare
  kind text;
  until timestamptz;
  n int;
begin
  if public.is_device() then
    kind := 'person';
  elsif public.is_platform_admin() and not public.is_service_role() and auth.uid() is not null then
    kind := 'display';
  else
    raise exception 'only a paired display or an admin can read messages';
  end if;
  if up_to is not null then
    select x.created_at into until from public.messages x where x.id = up_to;
    if until is null then raise exception 'message not found'; end if;
  end if;
  update public.messages x set read_at = now()
   where x.sender_kind = kind and x.read_at is null and (until is null or x.created_at <= until);
  get diagnostics n = row_count;
  return n;
end $$;

-- ───────────────────────────── Phones ─────────────────────────────

-- The signed-in person's phone (an app install) wants notifications: its
-- token as Apple gave it (hex, any case), which of Apple's hosts it's for
-- (`environment`: sandbox for a debug build, else production), the app's
-- bundle id and the platform. A token already kept moves to this person.
create function public.register_push_token(token text, environment text, bundle_id text, platform text default 'ios')
returns void
language plpgsql security definer set search_path = public as $$
declare
  t text := lower(btrim(coalesce(token, '')));
begin
  if not public.is_platform_admin() or public.is_service_role() or public.is_device() or auth.uid() is null then
    raise exception 'only the person gets notifications';
  end if;
  if t !~ '^[0-9a-f]{64,200}$' then raise exception 'that isn''t a device token'; end if;
  if environment not in ('sandbox', 'production') then raise exception 'environment must be sandbox or production'; end if;
  if coalesce(bundle_id, '') !~ '^[A-Za-z0-9][A-Za-z0-9.-]{0,154}$' then raise exception 'that isn''t a bundle id'; end if;
  if coalesce(platform, 'ios') not in ('ios', 'macos') then raise exception 'platform must be ios or macos'; end if;
  insert into public.push_tokens as p (token, user_id, environment, bundle_id, platform)
  values (t, auth.uid(), environment, bundle_id, coalesce(platform, 'ios'))
  on conflict on constraint push_tokens_pkey do update
    set user_id = excluded.user_id, environment = excluded.environment,
        bundle_id = excluded.bundle_id, platform = excluded.platform, updated_at = now();
end $$;

-- The signed-in person's phone no longer wants them (signing out). Returns
-- whether it was kept.
create function public.unregister_push_token(token text)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'sign in first'; end if;
  delete from public.push_tokens p where p.token = lower(btrim(coalesce(unregister_push_token.token, ''))) and p.user_id = auth.uid();
  return found;
end $$;

-- For the notify function (service role): a display's message as its
-- notification says it, the unread count for the badge, and every phone of
-- every admin. Null for a message that isn't a display's, or is gone.
create function public.message_push(message uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m public.messages;
begin
  if not public.is_service_role() then raise exception 'service only'; end if;
  select x.* into m from public.messages x where x.id = message;
  if m.id is null or m.sender_kind <> 'display' then return null; end if;
  return jsonb_build_object(
    'id', m.id,
    'sender_name', m.sender_name,
    'body', m.body,
    'created_at', m.created_at,
    'device_name', (select d.name from public.devices d where d.id = m.device_id),
    'displays', (select count(*) from public.devices),
    'unread', (select count(*) from public.messages x where x.sender_kind = 'display' and x.read_at is null),
    'tokens', coalesce((select jsonb_agg(jsonb_build_object('token', p.token, 'environment', p.environment,
                                                            'bundle_id', p.bundle_id, 'platform', p.platform)
                                         order by p.updated_at desc)
                        from public.push_tokens p join public.platform_admins a on a.user_id = p.user_id), '[]'));
end $$;

-- What became of a message's notification (service role): `error` null when
-- Apple took it for at least one phone, else why none went. Once it went,
-- a later error doesn't undo it.
create function public.message_notified(message uuid, error text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_service_role() then raise exception 'service only'; end if;
  update public.messages x
     set notified_at = case when error is null then coalesce(x.notified_at, now()) else x.notified_at end,
         notify_error = case when error is null or x.notified_at is not null then null else left(error, 300) end
   where x.id = message;
end $$;

-- Apple says a token is no longer good (the app was removed, or the token
-- was never this host's): forget it (service role).
create function public.push_token_gone(token text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_service_role() then raise exception 'service only'; end if;
  delete from public.push_tokens p where p.token = push_token_gone.token;
end $$;

-- After a display's message is in, ask the notify function to send it, as
-- calendar_sync_tick asks calendar-sync: the project's address and the cron
-- secret from Vault, through pg_net, which sends once the insert commits.
-- Without either (the local test run, a project not set up) nothing goes.
create function public.messages_notify()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  base text;
  secret text;
begin
  if to_regnamespace('vault') is null or to_regnamespace('net') is null then
    return null;
  end if;
  begin
    execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'mcfly_project_url'$q$ into base;
    execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'mcfly_cron_secret'$q$ into secret;
    if base is null or secret is null then
      return null;
    end if;
    execute $q$select net.http_post(url := $1, headers := $2, body := $3, timeout_milliseconds := 15000)$q$
      using rtrim(base, '/') || '/functions/v1/notify',
            jsonb_build_object('Content-Type', 'application/json', 'x-mcfly-cron', secret),
            jsonb_build_object('message', new.id);
  exception when others then
    raise warning 'messages_notify: %', sqlerrm;
  end;
  return null;
end $$;
create trigger messages_notify after insert on public.messages
  for each row when (new.sender_kind = 'display') execute function public.messages_notify();

revoke execute on function public.message_label(text, text) from public, anon;
revoke execute on function public.admin_set_message_names(text[]) from public, anon;
grant execute on function public.admin_set_message_names(text[]) to authenticated;
revoke execute on function public.set_message_name(text) from public, anon;
grant execute on function public.set_message_name(text) to authenticated;
revoke execute on function public.send_message(text, text, text) from public, anon;
grant execute on function public.send_message(text, text, text) to authenticated;
revoke execute on function public.read_messages(uuid) from public, anon;
grant execute on function public.read_messages(uuid) to authenticated;
revoke execute on function public.register_push_token(text, text, text, text) from public, anon;
grant execute on function public.register_push_token(text, text, text, text) to authenticated;
revoke execute on function public.unregister_push_token(text) from public, anon;
grant execute on function public.unregister_push_token(text) to authenticated;
revoke execute on function public.message_push(uuid) from public, anon, authenticated;
revoke execute on function public.message_notified(uuid, text) from public, anon, authenticated;
revoke execute on function public.push_token_gone(text) from public, anon, authenticated;
revoke execute on function public.messages_notify() from public, anon, authenticated;
