-- Dismissing what McFly calls out: a blocked project's "Needs you" and the
-- noticed lines (the console's insights, the display's highlights, the
-- app's). Each screen works those out from the feeds itself, under one id
-- scheme (`blocked:<project id>`, `metric:<key>`, `mover:<symbol>`, …), so a
-- dismissal is that id, and every screen hides an item while its id has a
-- row here that hasn't run out.
--
-- The server decides when a dismissal runs out, so the screens don't have
-- to agree on anything but the id:
--   blocked:<id>   until the project changes: its status or its next step
--                  (an agent re-sending the same project doesn't count)
--   anything else  until the end of today, in the account's time zone
--
-- A paired display dismisses through dismiss(), the second thing a display
-- may write after its own check-in time and settings.

create table public.dismissals (
  key           text primary key check (length(key) between 1 and 300 and key = lower(key)),
  hide_until    timestamptz,           -- null: until what it is about changes
  dismissed_at  timestamptz not null default now(),
  device_id     uuid references public.devices on delete set null
);

alter table public.dismissals enable row level security;
create policy dismissals_read on public.dismissals for select using (public.can_read());

-- Hide `item` (an insight's id, any case) on every screen. Returns the row's
-- key and when it runs out (null: when the project changes). Dismissing
-- again starts it over. Rows that have run out are pruned here.
create function public.dismiss(item text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  k text := lower(btrim(coalesce(item, '')));
  tz text;
  until timestamptz;
  device uuid;
begin
  if not (public.is_device() or public.is_platform_admin()) then
    raise exception 'only a paired display or an admin can dismiss';
  end if;
  if length(k) not between 1 and 300 then
    raise exception 'say what to dismiss (an id of 1 to 300 characters)';
  end if;
  if k like 'blocked:%' then
    until := null;
  else
    select s.timezone into tz from public.platform_settings s limit 1;
    if tz is null or not exists (select 1 from pg_timezone_names n where n.name = tz) then
      tz := 'UTC';
    end if;
    until := (date_trunc('day', now() at time zone tz) + interval '1 day') at time zone tz;
  end if;
  select d.id into device from public.devices d where d.user_id = auth.uid();
  insert into public.dismissals as x (key, hide_until, dismissed_at, device_id)
  values (k, until, now(), device)
  on conflict (key) do update set hide_until = excluded.hide_until, dismissed_at = excluded.dismissed_at, device_id = excluded.device_id;
  delete from public.dismissals x where x.hide_until is not null and x.hide_until < now();
  return jsonb_build_object('key', k, 'hide_until', until);
end $$;

-- A blocked project's dismissal ends when the project really changes (its
-- status or next step; not the updated_at every push touches) or goes.
create function public.projects_end_dismissal()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    delete from public.dismissals where key = 'blocked:' || old.id::text;
    return old;
  end if;
  if (new.status, new.next_step) is distinct from (old.status, old.next_step) then
    delete from public.dismissals where key = 'blocked:' || new.id::text;
  end if;
  return new;
end $$;

create trigger projects_end_dismissal_update after update on public.projects
  for each row execute function public.projects_end_dismissal();
create trigger projects_end_dismissal_delete after delete on public.projects
  for each row execute function public.projects_end_dismissal();

revoke execute on function public.dismiss(text) from public, anon;
grant execute on function public.dismiss(text) to authenticated;
revoke execute on function public.projects_end_dismissal() from public, anon, authenticated;
