-- Away mode from a display: on the way out the door, the person taps "I'm
-- heading out" on the screen at home, and "I'm home" when they're back.
-- set_away() stays the person's own (the app, the console, Shortcuts); this
-- is the display's way in, with the same limits and no note (there's no
-- typing on the way out). Anyone at the screen can tap it, kids too: all it
-- does is put Messages first and say who's out.
--
-- A display has no person, so the name on it is the household's name for
-- the person: the first admin's message name, else "Parent". On again while
-- already away keeps when it began, the name and the note.

create function public.device_set_away(away boolean, until timestamptz default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  device text;
  who text;
  s public.platform_settings;
begin
  select d.name into device from public.devices d where d.user_id = auth.uid();
  if auth.uid() is null or device is null then raise exception 'not a paired display'; end if;
  if device_set_away.away is null then raise exception 'say whether you''re away'; end if;
  if device_set_away.away then
    if device_set_away.until is not null and device_set_away.until <= now() then
      raise exception 'pick a time that hasn''t passed';
    end if;
    if device_set_away.until is not null and device_set_away.until > now() + interval '14 days' then
      raise exception 'away for at most two weeks at a time';
    end if;
    select p.message_name into who
      from public.platform_admins a join public.profiles p on p.id = a.user_id
     where p.message_name is not null
     order by p.created_at, p.id
     limit 1;
    update public.platform_settings x
       set away_since = case when x.away_since is not null and (x.away_until is null or x.away_until > now())
                             then x.away_since else now() end,
           away_name = case when x.away_since is not null and (x.away_until is null or x.away_until > now())
                            then x.away_name else coalesce(who, 'Parent') end,
           away_note = case when x.away_since is not null and (x.away_until is null or x.away_until > now())
                            then x.away_note end,
           away_until = device_set_away.until,
           updated_at = now(),
           updated_by = auth.uid()
     where x.id
    returning x.* into s;
  else
    update public.platform_settings x
       set away_since = null, away_until = null, away_note = null, away_name = null,
           updated_at = now(), updated_by = auth.uid()
     where x.id
    returning x.* into s;
  end if;
  perform public.log_admin_action('set_away', 'settings', null,
    jsonb_build_object('away', device_set_away.away, 'until', device_set_away.until, 'display', device));
  return jsonb_build_object('away', s.away_since is not null, 'since', s.away_since, 'until', s.away_until,
                            'note', s.away_note, 'name', s.away_name);
end $$;

revoke execute on function public.device_set_away(boolean, timestamptz) from public, anon;
grant execute on function public.device_set_away(boolean, timestamptz) to authenticated;
