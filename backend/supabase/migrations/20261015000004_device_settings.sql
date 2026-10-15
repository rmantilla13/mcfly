-- Per-display settings, kept on the server so the web and the display edit
-- the same thing. Until now every one of these lived only on the Pi.
--
-- A fixed list of keys, each with its type and range (clean_device_settings).
-- The admin changes any display's; a display changes only its own, through
-- device_update_settings: the devices_guard trigger still lets a display
-- update nothing on its row but last_seen_at directly.
--
--   screensaver        ambient | clock | headlines
--   darkMode           boolean
--   animatedTiles      boolean
--   idleSeconds        30..3600       before the screen saver
--   offAfterSeconds    0..86400       0 = never turn the screen off
--   offAtNight         boolean
--   bedtime, wakeTime  0..1439        minutes after midnight
--   assistantProvider  "" | claude | grok    "" = the account's choice
--   speakReplies       boolean
--   wakeword           boolean
--   wakewordModel      hey_jarvis | alexa | hey_mycroft | hey_rhasspy
--   voice              af_heart | af_bella | am_michael | am_fenrir   (Kokoro: Homestead's voices)
--   voiceSpeed         0.5..2.0
--   volume             0..100

alter table public.devices add column if not exists settings jsonb not null default '{}';

create or replace function public.clean_device_settings(patch jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  k text;
  v jsonb;
  out jsonb := '{}';
  n numeric;
begin
  if patch is null or jsonb_typeof(patch) <> 'object' then raise exception 'settings must be an object'; end if;
  for k, v in select * from jsonb_each(patch) loop
    case k
      when 'screensaver' then
        if v #>> '{}' not in ('ambient', 'clock', 'headlines') then raise exception 'screensaver must be ambient, clock or headlines'; end if;
      when 'assistantProvider' then
        if jsonb_typeof(v) <> 'string' or v #>> '{}' not in ('', 'claude', 'grok') then raise exception 'assistantProvider must be "", claude or grok'; end if;
      when 'voice' then
        if v #>> '{}' not in ('af_heart', 'af_bella', 'am_michael', 'am_fenrir') then
          raise exception 'voice must be af_heart, af_bella, am_michael or am_fenrir';
        end if;
      when 'wakewordModel' then
        if v #>> '{}' not in ('hey_jarvis', 'alexa', 'hey_mycroft', 'hey_rhasspy') then
          raise exception 'wakewordModel must be hey_jarvis, alexa, hey_mycroft or hey_rhasspy';
        end if;
      when 'darkMode', 'animatedTiles', 'offAtNight', 'speakReplies', 'wakeword' then
        if jsonb_typeof(v) <> 'boolean' then raise exception '% must be true or false', k; end if;
      when 'idleSeconds', 'offAfterSeconds', 'bedtime', 'wakeTime', 'volume' then
        if jsonb_typeof(v) <> 'number' then raise exception '% must be a number', k; end if;
        n := (v #>> '{}')::numeric;
        if n <> trunc(n)
           or (k = 'idleSeconds' and n not between 30 and 3600)
           or (k = 'offAfterSeconds' and n not between 0 and 86400)
           or (k in ('bedtime', 'wakeTime') and n not between 0 and 1439)
           or (k = 'volume' and n not between 0 and 100) then
          raise exception '% is out of range', k;
        end if;
      when 'voiceSpeed' then
        if jsonb_typeof(v) <> 'number' or (v #>> '{}')::numeric not between 0.5 and 2.0 then raise exception 'voiceSpeed must be 0.5 to 2.0'; end if;
      else
        continue; -- unknown keys are dropped, so an older server ignores a newer display's extras
    end case;
    out := out || jsonb_build_object(k, v);
  end loop;
  return out;
end $$;

drop function if exists public.admin_list_devices();
create function public.admin_list_devices()
returns table (id uuid, user_id uuid, name text, last_seen_at timestamptz, created_at timestamptz, settings jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query select d.id, d.user_id, d.name, d.last_seen_at, d.created_at, d.settings from public.devices d order by d.created_at, d.id;
end $$;
revoke execute on function public.admin_list_devices() from public, anon;
grant execute on function public.admin_list_devices() to authenticated;

create function public.admin_update_device_settings(device uuid, patch jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  saved jsonb;
  clean jsonb := public.clean_device_settings(patch);
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  update public.devices d set settings = d.settings || clean where d.id = device returning d.settings into saved;
  if saved is null then raise exception 'display not found'; end if;
  perform public.log_admin_action('update_device_settings', 'device', device::text, clean);
  return saved;
end $$;

-- A display's own settings, from the display (its own JWT).
create function public.device_update_settings(patch jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  saved jsonb;
  clean jsonb := public.clean_device_settings(patch);
begin
  -- The guard trigger only allows last_seen_at changes from a display's own
  -- session; this function is the one other way in, so it says so.
  perform set_config('mcfly.device_settings', 'on', true);
  update public.devices d set settings = d.settings || clean where d.user_id = auth.uid() returning d.settings into saved;
  if saved is null then raise exception 'not a paired display'; end if;
  return saved;
end $$;

revoke execute on function public.clean_device_settings(jsonb) from public, anon, authenticated;
revoke execute on function public.admin_update_device_settings(uuid, jsonb) from public, anon;
revoke execute on function public.device_update_settings(jsonb) from public, anon;
grant execute on function public.admin_update_device_settings(uuid, jsonb) to authenticated;
grant execute on function public.device_update_settings(jsonb) to authenticated;

-- The guard compared only the columns that existed when it was written, so a
-- display could have written `settings` straight through its update policy,
-- unchecked. Now only device_update_settings may change them.
create or replace function public.devices_guard()
returns trigger
language plpgsql set search_path = public as $$
begin
  if public.is_platform_admin() then
    return new;
  end if;
  if (new.id, new.user_id, new.name, new.created_at) is distinct from (old.id, old.user_id, old.name, old.created_at) then
    raise exception 'a display can only update its check-in time';
  end if;
  if new.settings is distinct from old.settings and current_setting('mcfly.device_settings', true) is distinct from 'on' then
    raise exception 'a display changes its settings through device_update_settings';
  end if;
  return new;
end $$;
