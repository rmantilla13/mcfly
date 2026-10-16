-- "Hey McFly" becomes a wake word a display can use: McFly's own model, the
-- voice service's default from now on. clean_device_settings is restated
-- whole (20261015000004) with hey_mcfly added to wakewordModel:
--
--   wakewordModel      hey_mcfly | hey_jarvis | alexa | hey_mycroft | hey_rhasspy
--
-- Saved settings are left as they are. A display that stored hey_jarvis
-- keeps it until someone picks Hey McFly (the console's Customize): a Pi
-- still on the older voice service would refuse hey_mcfly, every minute.

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
        if v #>> '{}' not in ('hey_mcfly', 'hey_jarvis', 'alexa', 'hey_mycroft', 'hey_rhasspy') then
          raise exception 'wakewordModel must be hey_mcfly, hey_jarvis, alexa, hey_mycroft or hey_rhasspy';
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

revoke execute on function public.clean_device_settings(jsonb) from public, anon, authenticated;
