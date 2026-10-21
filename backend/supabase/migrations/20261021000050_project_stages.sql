-- Projects get stages: the steps an agent lays out for a project (Plan,
-- Build, Review, Ship) and the one it is in now. Stages before the current
-- one read as done, a done project has been through them all, and a blocked
-- one is stuck in the stage it is in. `stage_since` is when the project
-- reached that stage, so a list can say "in Review for 3 days".
--
-- A push without `stages` keeps the project's stages, and one without
-- `stage` keeps its stage (cleared when new stages no longer name it), so an
-- agent that only reports status doesn't wipe what another push set.

-- A project's stages: up to 12 distinct names (case aside) of 1 to 40
-- characters, in order. Used by the table's check and by ingest.
create function public.valid_project_stages(s jsonb)
returns boolean
language sql immutable as $$
  select jsonb_typeof(s) = 'array'
     and jsonb_array_length(s) <= 12
     and not exists (select 1 from jsonb_array_elements(s) e
                      where jsonb_typeof(e) <> 'string' or length(e #>> '{}') not between 1 and 40 or e #>> '{}' <> btrim(e #>> '{}'))
     and (select count(distinct lower(e)) from jsonb_array_elements_text(s) e) = jsonb_array_length(s);
$$;

alter table public.projects
  add column stages      jsonb not null default '[]',
  add column stage       text,
  add column stage_since timestamptz;

alter table public.projects
  add constraint projects_stages_valid check (public.valid_project_stages(stages)),
  add constraint projects_stage_listed check (stage is null or stages ? stage);

-- An agent's stages, trimmed, or a sentence on what's wrong with them.
create function public.clean_project_stages(raw jsonb, project text)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  cleaned jsonb := '[]';
  e jsonb;
  name text;
begin
  if raw is null or jsonb_typeof(raw) = 'null' then return '[]'; end if;
  if jsonb_typeof(raw) <> 'array' then raise exception 'project %: stages must be a list of names', project; end if;
  if jsonb_array_length(raw) > 12 then raise exception 'project %: at most 12 stages', project; end if;
  for e in select * from jsonb_array_elements(raw) loop
    name := case when jsonb_typeof(e) = 'string' then btrim(e #>> '{}') end;
    if name is null or length(name) not between 1 and 40 then
      raise exception 'project %: each stage must be a name of 1 to 40 characters', project;
    end if;
    if exists (select 1 from jsonb_array_elements_text(cleaned) x where lower(x) = lower(name)) then
      raise exception 'project %: stage "%" is listed twice', project, name;
    end if;
    cleaned := cleaned || to_jsonb(name);
  end loop;
  return cleaned;
end $$;

-- projects: [{ key, name, kind?, status?, progress?, summary?, next_step?,
-- link?, color?, sort_order?, data?, stages?, stage?, updates?: [{ kind?, text, url?, at? }] }]
create or replace function public.ingest_projects(agent uuid, items jsonb)
returns int
language plpgsql security definer set search_path = public as $$
declare
  item jsonb;
  u jsonb;
  pid uuid;
  n int := 0;
  k int;
  pkey text;
  old_stages jsonb;
  old_stage text;
  old_since timestamptz;
  new_stages jsonb;
  wanted text;
  new_stage text;
  new_since timestamptz;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  if jsonb_typeof(items) <> 'array' then raise exception 'projects must be a list'; end if;
  if jsonb_array_length(items) > 100 then raise exception 'at most 100 projects per push'; end if;
  for item in select * from jsonb_array_elements(items) loop
    if jsonb_typeof(item) <> 'object' then raise exception 'each project must be an object'; end if;
    pkey := btrim(item->>'key');

    -- Stages: this push's when it sends them, else the project's own; the
    -- stage it names (any case) or the one it was in.
    old_stages := null; old_stage := null; old_since := null;
    select p.stages, p.stage, p.stage_since into old_stages, old_stage, old_since
      from public.projects p where p.agent_id = agent and p.key = pkey;
    new_stages := case when item ? 'stages' then public.clean_project_stages(item->'stages', pkey) else coalesce(old_stages, '[]') end;
    wanted := case when item ? 'stage' then nullif(btrim(item->>'stage'), '') else old_stage end;
    new_stage := (select s from jsonb_array_elements_text(new_stages) s where lower(s) = lower(wanted) limit 1);
    if item ? 'stage' and wanted is not null and new_stage is null then
      if jsonb_array_length(new_stages) = 0 then
        raise exception 'project %: a stage needs stages to be one of', pkey;
      end if;
      raise exception 'project %: stage "%" is not one of its stages', pkey, wanted;
    end if;
    new_since := case when new_stage is null then null
                      when new_stage is distinct from old_stage then now()
                      else coalesce(old_since, now()) end;

    insert into public.projects as p (agent_id, key, name, kind, status, progress, summary, next_step, link, color, sort_order, data,
                                      stages, stage, stage_since)
    values (agent,
            pkey,
            left(btrim(coalesce(item->>'name', item->>'key')), 120),
            coalesce(nullif(btrim(item->>'kind'), ''), 'other'),
            coalesce(nullif(btrim(item->>'status'), ''), 'active'),
            (item->>'progress')::int,
            left(coalesce(item->>'summary', ''), 2000),
            nullif(left(item->>'next_step', 500), ''),
            nullif(btrim(item->>'link'), ''),
            nullif(btrim(item->>'color'), ''),
            coalesce((item->>'sort_order')::int, 1000),
            coalesce(case when jsonb_typeof(item->'data') = 'object' then item->'data' end, '{}'),
            new_stages, new_stage, new_since)
    on conflict (agent_id, key) do update
      set name = excluded.name, kind = excluded.kind, status = excluded.status, progress = excluded.progress,
          summary = excluded.summary, next_step = excluded.next_step, link = excluded.link,
          color = coalesce(excluded.color, p.color), sort_order = excluded.sort_order, data = excluded.data,
          stages = excluded.stages, stage = excluded.stage, stage_since = excluded.stage_since
    returning p.id into pid;
    if jsonb_typeof(item->'updates') = 'array' then
      k := 0;
      for u in select * from jsonb_array_elements(item->'updates') loop
        exit when k >= 20;
        if jsonb_typeof(u) = 'object' and nullif(btrim(u->>'text'), '') is not null then
          -- The same line again (an agent re-sending its log) is not a new update.
          if not exists (select 1 from public.project_updates x where x.project_id = pid
                           and x.text = left(btrim(u->>'text'), 2000)
                           and x.happened_at = public.read_timestamp(u->'at', now())) then
            insert into public.project_updates (project_id, kind, text, url, happened_at)
            values (pid, coalesce(nullif(btrim(u->>'kind'), ''), 'note'), left(btrim(u->>'text'), 2000),
                    nullif(btrim(u->>'url'), ''), public.read_timestamp(u->'at', now()));
          end if;
          k := k + 1;
        end if;
      end loop;
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;

-- The console's list, now with each project's stages.
drop function public.admin_list_projects();
create function public.admin_list_projects()
returns table (id uuid, agent_id uuid, agent_name text, agent_color text, key text, name text, kind text, status text, progress int,
               summary text, next_step text, link text, color text, sort_order int, updated_at timestamptz, update_count int,
               last_update text, last_update_at timestamptz, stages jsonb, stage text, stage_since timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query
    select p.id, p.agent_id, a.name, a.color, p.key, p.name, p.kind, p.status, p.progress, p.summary, p.next_step, p.link, p.color,
           p.sort_order, p.updated_at,
           (select count(*)::int from public.project_updates u where u.project_id = p.id),
           (select u.text from public.project_updates u where u.project_id = p.id order by u.happened_at desc, u.id desc limit 1),
           (select u.happened_at from public.project_updates u where u.project_id = p.id order by u.happened_at desc, u.id desc limit 1),
           p.stages, p.stage, p.stage_since
    from public.projects p join public.agents a on a.id = p.agent_id
    order by (p.status = 'done'), p.sort_order, p.updated_at desc;
end $$;

revoke execute on function public.clean_project_stages(jsonb, text) from public, anon, authenticated;
revoke execute on function public.ingest_projects(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.admin_list_projects() from public, anon;
