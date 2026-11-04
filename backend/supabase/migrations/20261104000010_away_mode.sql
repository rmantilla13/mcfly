-- Away mode: the person says they're out of the house, and the displays
-- put Messages first (the screen wakes to it, the screen saver says how to
-- reach them). Set from the app, the console or an iOS Shortcuts
-- automation (leaving home, arriving home) through set_away().
--
-- It lives on platform_settings, which displays read: away from away_since
-- until away_until (null: until it's turned off). Each screen decides
-- "still away" against away_until itself, so it ends on time without a
-- write. away_name is what the household calls the person who set it,
-- copied in because displays can't read profiles.

alter table public.platform_settings
  add column away_since timestamptz,
  add column away_until timestamptz,
  add column away_note  text check (away_note is null or (length(away_note) between 1 and 80 and away_note !~ '[\x01-\x1f\x7f]')),
  add column away_name  text check (away_name is null or length(away_name) between 1 and 24),
  add check ((away_since is null) = (away_name is null)),
  add check (away_since is not null or (away_until is null and away_note is null));

-- Turn away mode on (until a time, or until it's turned off) or off. Only
-- the person (an admin's own sign-in), never a display. On again while
-- already away keeps when it began; a time that has passed, or more than
-- two weeks out, is refused. `note` is one line of up to 80 characters
-- ("At work"); blank clears it. Returns the setting as it now stands.
create function public.set_away(away boolean, until timestamptz default null, note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  n text := nullif(btrim(coalesce(set_away.note, '')), '');
  who text;
  s public.platform_settings;
begin
  if not public.is_platform_admin() or public.is_service_role() or auth.uid() is null then
    raise exception 'only the person can say they''re away';
  end if;
  if set_away.away is null then raise exception 'say whether you''re away'; end if;
  if set_away.away then
    if set_away.until is not null and set_away.until <= now() then
      raise exception 'pick a time that hasn''t passed';
    end if;
    if set_away.until is not null and set_away.until > now() + interval '14 days' then
      raise exception 'away for at most two weeks at a time';
    end if;
    if n ~ '[\x01-\x1f\x7f]' then raise exception 'the note must be one line'; end if;
    if length(n) > 80 then raise exception 'the note can be at most 80 characters'; end if;
    select p.message_name into who from public.profiles p where p.id = auth.uid();
    update public.platform_settings x
       set away_since = case when x.away_since is not null and (x.away_until is null or x.away_until > now())
                             then x.away_since else now() end,
           away_until = set_away.until,
           away_note = n,
           away_name = coalesce(who, 'Parent'),
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
    jsonb_build_object('away', set_away.away, 'until', set_away.until, 'note', n));
  return jsonb_build_object('away', s.away_since is not null, 'since', s.away_since, 'until', s.away_until,
                            'note', s.away_note, 'name', s.away_name);
end $$;

revoke execute on function public.set_away(boolean, timestamptz, text) from public, anon;
grant execute on function public.set_away(boolean, timestamptz, text) to authenticated;
