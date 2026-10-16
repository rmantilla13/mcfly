-- Dashboards made in the console. The person picks a template and, for each
-- part of the board, where it pulls from: symbols, metrics, projects,
-- calendars, todos, the news, a brief, the agents' health, or a note of
-- their own. McFly draws those parts into the same six widgets an agent
-- sends (metric, status, progress, chart, list, text), so the display, the
-- apps and the console show a made board exactly as they show a pushed one,
-- with nothing new to learn. It redraws the board whenever what it pulls from
-- changes, and every minute for "today" and "next".
--
-- `sources` is the board's recipe: a list of parts, each { from, ... }
-- (docs/AGENTS.md, "Dashboards you make"). Null means an agent lays the
-- board out itself, as before. `template` names the console's starting
-- point. Made boards belong to McFly's own agent (mcfly_agent()), which has
-- no key, and an agent's push can't take one over.
--
-- Nothing from an earlier migration changes except admin_list_dashboards,
-- which also returns the two new columns.

alter table public.dashboards
  add column if not exists template text check (template is null or template ~ '^[a-z0-9][a-z0-9-]{0,39}$'),
  add column if not exists sources  jsonb check (sources is null or (jsonb_typeof(sources) = 'array' and jsonb_array_length(sources) between 1 and 20));

-- ───────────────────────────── Drawing ─────────────────────────────

-- The display's time zone: "today" and the times on a list are its.
create or replace function public.dashboard_zone()
returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select s.timezone from public.platform_settings s limit 1), 'UTC')
$$;

-- "Today 9:30 AM", "Tomorrow", "Tue Oct 20 2:00 PM": a time on a list.
create or replace function public.dashboard_when(at timestamptz, all_day boolean, zone text)
returns text
language sql stable set search_path = public as $$
  select case (at at time zone zone)::date - (now() at time zone zone)::date
           when 0 then 'Today' when 1 then 'Tomorrow' when -1 then 'Yesterday'
           else to_char(at at time zone zone, 'Dy Mon FMDD') end
         || case when all_day then '' else ' ' || to_char(at at time zone zone, 'FMHH12:MI AM') end
$$;

-- A part's list of names (symbols, keys, calendars, ids), trimmed, in the
-- person's order, at most `most`.
create or replace function public.dashboard_strings(j jsonb, most int)
returns text[]
language sql immutable set search_path = public as $$
  select coalesce(array_agg(left(btrim(t.v), 200) order by t.i), '{}')
  from jsonb_array_elements_text(case when jsonb_typeof(j) = 'array' then j else '[]'::jsonb end) with ordinality t(v, i)
  where btrim(t.v) <> '' and t.i <= most
$$;

-- A whole number from a part, kept between lo and hi.
create or replace function public.dashboard_int(j jsonb, fallback int, lo int, hi int)
returns int
language sql immutable set search_path = public as $$
  select least(greatest(coalesce(case when jsonb_typeof(j) = 'number' then floor(j::text::numeric)::int
                                      when jsonb_typeof(j) = 'string' and j #>> '{}' ~ '^\s*-?\d{1,6}\s*$' then (j #>> '{}')::int end,
                                 fallback), lo), hi)
$$;

-- A part with nothing to show still shows its card, saying so: a board
-- always has a widget (the table's check), and the person sees which part
-- is waiting rather than a gap.
create or replace function public.dashboard_waiting(title text, body text)
returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('type', 'text', 'title', title, 'body', body)))
$$;

-- One part of a made board, drawn: a list of widgets.
create or replace function public.dashboard_part(part jsonb, zone text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  src text := part->>'from';
  heading text := nullif(left(btrim(coalesce(part->>'title', '')), 80), '');
  show text := coalesce(part->>'show', '');
  names text[];
  lim int;
  days int;
  hours int;
  sel text;
  drawn jsonb;
begin
  case src
  when 'quotes' then
    names := public.dashboard_strings(part->'symbols', 20);
    lim := public.dashboard_int(part->'limit', case when show = 'chart' then 1 else 8 end, 1, 12);
    with picked as (
      select upper(n) as symbol, i from unnest(names) with ordinality u(n, i)
      union all
      select s.symbol, 1000 + row_number() over (order by s.sort_order, s.symbol) from public.symbols s
       where cardinality(names) = 0 and not s.hidden
    )
    select jsonb_agg(x.w order by x.i) into drawn from (
      select p.i,
             case when show = 'chart' then
               jsonb_build_object('type', 'chart', 'label', coalesce(q.name || ' (' || q.symbol || ')', q.symbol), 'unit', q.currency,
                 'points', (select jsonb_agg(h.price order by h.as_of, h.id)
                              from (select hq.price, hq.as_of, hq.id from public.quotes hq
                                     where hq.symbol = q.symbol and hq.as_of > now() - interval '30 days'
                                     order by hq.as_of desc, hq.id desc limit 120) h))
             else
               jsonb_strip_nulls(jsonb_build_object('type', 'metric', 'label', q.symbol, 'value', q.price, 'unit', q.currency,
                                                    'delta', q.change, 'delta_pct', q.change_pct))
             end as w
      from picked p join public.quotes_latest q on q.symbol = p.symbol
      order by p.i limit lim
    ) x;
    return coalesce(drawn, public.dashboard_waiting(coalesce(heading, 'Markets'),
      case when cardinality(names) = 0 then 'No quotes yet.' else 'No quotes yet for ' || array_to_string(names, ', ') || '.' end));

  when 'metrics' then
    names := public.dashboard_strings(part->'keys', 20);
    sel := nullif(btrim(coalesce(part->>'group', '')), '');
    lim := public.dashboard_int(part->'limit', case when show = 'chart' then 2 else 8 end, 1, 12);
    with picked as (
      select lower(n) as key, i from unnest(names) with ordinality u(n, i)
      union all
      select ms.key, 1000 + row_number() over (order by ms.sort_order, ms.key) from public.metric_settings ms
       where cardinality(names) = 0 and not ms.hidden and (sel is null or ms.group_name = sel)
    )
    select jsonb_agg(x.w order by x.i) into drawn from (
      select p.i,
             case when show = 'chart' then
               jsonb_strip_nulls(jsonb_build_object('type', 'chart', 'label', coalesce(ms.label, m.label, m.key), 'unit', m.unit,
                 'points', (select jsonb_agg(h.value order by h.as_of, h.id)
                              from (select hm.value, hm.as_of, hm.id from public.metrics hm
                                     where hm.key = m.key order by hm.as_of desc, hm.id desc limit 120) h)))
             else
               jsonb_strip_nulls(jsonb_build_object('type', 'metric', 'label', coalesce(ms.label, m.label, m.key), 'value', m.value,
                                                    'unit', m.unit, 'delta', m.delta, 'delta_pct', m.delta_pct))
             end as w
      from picked p join public.metrics_latest m on m.key = p.key
      left join public.metric_settings ms on ms.key = m.key
      order by p.i limit lim
    ) x;
    return coalesce(drawn, public.dashboard_waiting(coalesce(heading, sel, 'Metrics'), 'No numbers yet.'));

  when 'projects' then
    names := public.dashboard_strings(part->'projects', 20);
    lim := public.dashboard_int(part->'limit', 6, 1, 12);
    with picked as (
      select pr.*, u.i from unnest(names) with ordinality u(n, i)
        join public.projects pr on n ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' and pr.id = n::uuid
      union all
      select pr.*, 1000 + row_number() over (order by pr.sort_order, pr.name) from public.projects pr
       where cardinality(names) = 0 and pr.status in ('active', 'blocked')
    ), shown as (
      select * from picked order by i limit lim
    )
    select case when show = 'list' then
             (select jsonb_build_array(jsonb_build_object('type', 'list', 'title', coalesce(heading, 'Projects'),
                       'items', jsonb_agg(s.name || coalesce(' · ' || s.next_step, '') order by s.i)))
                from shown s having count(*) > 0)
           else
             (select jsonb_agg(case when s.progress is not null then
                       jsonb_build_object('type', 'progress', 'label', s.name, 'value', s.progress, 'max', 100, 'unit', '%')
                     else
                       jsonb_strip_nulls(jsonb_build_object('type', 'status', 'label', s.name,
                         'state', case s.status when 'blocked' then 'warn' when 'paused' then 'unknown' else 'ok' end,
                         'detail', left(coalesce(s.next_step, nullif(s.summary, '')), 300)))
                     end order by s.i)
                from shown s)
           end into drawn;
    return coalesce(drawn, public.dashboard_waiting(coalesce(heading, 'Projects'), 'No projects yet.'));

  when 'calendar' then
    names := public.dashboard_strings(part->'calendars', 20);
    days := public.dashboard_int(part->'days', 7, 1, 31);
    lim := public.dashboard_int(part->'limit', 8, 1, 20);
    heading := coalesce(heading, case days when 1 then 'Today' when 2 then 'Today and tomorrow' else 'Next ' || days || ' days' end);
    select jsonb_build_array(jsonb_build_object('type', 'list', 'title', heading,
             'items', jsonb_agg(public.dashboard_when(e.starts_at, e.all_day, zone) || ' · ' || e.title order by e.starts_at, e.title)))
      into drawn
      from (select ev.* from public.events ev
             where ev.ends_at > now()
               and ev.starts_at < (date_trunc('day', now() at time zone zone) + make_interval(days => days)) at time zone zone
               and (cardinality(names) = 0 or ev.calendar = any (names))
             order by ev.starts_at, ev.title limit lim) e
    having count(*) > 0;
    return coalesce(drawn, public.dashboard_waiting(heading, 'Nothing on the calendar.'));

  when 'todos' then
    sel := coalesce(nullif(part->>'kind', ''), 'all');
    if sel not in ('todo', 'reminder', 'all') then sel := 'all'; end if;
    lim := public.dashboard_int(part->'limit', 8, 1, 20);
    heading := coalesce(heading, case sel when 'reminder' then 'Reminders' else 'To do' end);
    select jsonb_build_array(jsonb_build_object('type', 'list', 'title', heading,
             'items', jsonb_agg(t.title || coalesce(' · ' || public.dashboard_when(t.due_at, t.all_day, zone), '') order by t.n)))
      into drawn
      from (select td.*, row_number() over (order by td.due_at nulls last, td.created_at, td.id) as n from public.todos td
             where td.done_at is null and (sel = 'all' or td.kind = sel)
             order by td.due_at nulls last, td.created_at, td.id limit lim) t
    having count(*) > 0;
    return coalesce(drawn, public.dashboard_waiting(heading, case sel when 'reminder' then 'No reminders set.' else 'Nothing open.' end));

  when 'news' then
    sel := nullif(btrim(coalesce(part->>'section', '')), '');
    lim := public.dashboard_int(part->'limit', 5, 1, 20);
    select jsonb_build_array(jsonb_build_object('type', 'list',
             'title', coalesce(heading, case when sel is null then 'Headlines' else min(i.section_name) end),
             'items', jsonb_agg(i.headline order by i.section_order, i.position)))
      into drawn
      from (select ni.* from public.news_items ni
             where ni.report_id = (select r.id from public.news_reports r order by r.report_date desc, r.published_at desc limit 1)
               and (sel is null or ni.section_key = sel)
             order by ni.section_order, ni.position limit lim) i
    having count(*) > 0;
    return coalesce(drawn, public.dashboard_waiting(coalesce(heading, 'Headlines'), 'No headlines yet.'));

  when 'brief' then
    sel := nullif(part->>'kind', '');
    names := public.dashboard_strings(jsonb_build_array(part->>'agent'), 1);
    select jsonb_build_array(jsonb_build_object('type', 'text', 'title', left(coalesce(heading, b.title), 80), 'body', left(b.body, 2000)))
      into drawn
      from public.briefs b
     where (b.expires_at is null or b.expires_at > now())
       and (sel is null or b.kind = sel)
       and (cardinality(names) = 0 or b.agent_id::text = names[1])
     order by b.published_at desc limit 1;
    return coalesce(drawn, public.dashboard_waiting(coalesce(heading, 'Brief'), 'No brief yet.'));

  when 'agents' then
    names := public.dashboard_strings(part->'agents', 20);
    hours := public.dashboard_int(part->'hours', 24, 1, 720);
    with picked as (
      select a.id, a.name, u.i from unnest(names) with ordinality u(n, i) join public.agents a on a.id::text = n
      union all
      select a.id, a.name, 1000 + row_number() over (order by a.name) from public.agents a
       where cardinality(names) = 0 and a.revoked_at is null and exists (select 1 from public.agent_keys k where k.agent_id = a.id)
    )
    select jsonb_agg(jsonb_build_object('type', 'status', 'label', p.name,
             'state', case when l.created_at is null then 'unknown' when l.status = 'error' then 'down'
                           when l.created_at < now() - make_interval(hours => hours) then 'warn' else 'ok' end,
             'detail', case when l.created_at is null then 'No pushes yet'
                            when l.status = 'error' then left('Last push failed: ' || coalesce(l.message, 'no reason given'), 300)
                            when l.created_at < now() - make_interval(hours => hours) then 'Quiet since ' || public.dashboard_when(l.created_at, false, zone)
                            else 'Last push ' || public.dashboard_when(l.created_at, false, zone) end)
             order by p.i)
      into drawn
      from (select * from picked order by i limit 12) p
      left join lateral (select g.created_at, g.status, g.message from public.ingest_log g
                          where g.agent_id = p.id order by g.created_at desc, g.id desc limit 1) l on true;
    return coalesce(drawn, public.dashboard_waiting(coalesce(heading, 'Agents'), 'No agents yet.'));

  when 'note' then
    return public.dashboard_waiting(heading, coalesce(nullif(left(btrim(coalesce(part->>'body', '')), 2000), ''), ' '));

  else
    return '[]'::jsonb;
  end case;
end $$;

-- A made board's widgets, part by part. A part that fails says so on its
-- card rather than taking the board (or whatever write set off the redraw)
-- down with it. At most 40, the table's limit.
create or replace function public.dashboard_widgets(sources jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  zone text := public.dashboard_zone();
  part jsonb;
  drawn jsonb := '[]';
begin
  if jsonb_typeof(sources) = 'array' then
    for part in select * from jsonb_array_elements(sources) loop
      begin
        if jsonb_typeof(part) = 'object' then
          drawn := drawn || public.dashboard_part(part, zone);
        end if;
      exception when others then
        raise warning 'dashboard part % was not drawn: %', part->>'from', sqlerrm;
        drawn := drawn || public.dashboard_waiting(coalesce(nullif(part->>'title', ''), 'This part'), 'Could not be drawn just now.');
      end;
    end loop;
  end if;
  if jsonb_array_length(drawn) = 0 then
    return public.dashboard_waiting(null, 'Nothing to show yet.');
  end if;
  if jsonb_array_length(drawn) > 40 then
    select jsonb_agg(w order by i) into drawn from jsonb_array_elements(drawn) with ordinality t(w, i) where i <= 40;
  end if;
  return drawn;
end $$;

-- Every made board, redrawn; only the ones whose widgets changed are
-- written, so a display hears of a board when it looks different.
create or replace function public.render_made_dashboards()
returns int
language plpgsql security definer set search_path = public as $$
declare
  n int;
begin
  update public.dashboards d
     set widgets = w.widgets
    from (select x.id, public.dashboard_widgets(x.sources) as widgets from public.dashboards x where x.sources is not null) w
   where d.id = w.id and d.widgets is distinct from w.widgets;
  get diagnostics n = row_count;
  return n;
end $$;

-- ───────────────────────────── Redrawing ─────────────────────────────

-- A write to anything a made board pulls from redraws the boards once, at
-- the end of its transaction: a push of a thousand events draws once, after
-- the last. (A constraint trigger is the only kind Postgres defers to
-- commit; the session setting holds the transaction that already drew.)
-- A redraw that fails is a warning, never the writer's error: an agent's
-- push must not fail over a board.
create or replace function public.dashboards_redraw_soon()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if current_setting('mcfly.dashboards_drawn', true) = txid_current()::text then
    return null;
  end if;
  perform set_config('mcfly.dashboards_drawn', txid_current()::text, false);
  begin
    perform public.render_made_dashboards();
  exception when others then
    raise warning 'made dashboards were not redrawn: %', sqlerrm;
  end;
  return null;
end $$;

do $$
declare
  t text;
begin
  foreach t in array array['quotes', 'symbols', 'metrics', 'metric_settings', 'projects', 'events', 'todos',
                           'news_reports', 'news_items', 'briefs', 'agents', 'ingest_log'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_redraw_dashboards', t);
    execute format('create constraint trigger %I after insert or update or delete on public.%I '
                   'deferrable initially deferred for each row execute function public.dashboards_redraw_soon()',
                   t || '_redraw_dashboards', t);
  end loop;
end $$;

-- An agent pushing a made board's key would swap its widgets for the
-- agent's, and the next redraw would swap them back. Refuse it instead.
create or replace function public.dashboards_keep_made()
returns trigger
language plpgsql set search_path = public as $$
begin
  if old.sources is not null and new.agent_id is distinct from old.agent_id then
    raise exception 'dashboard % is made in the console; push yours under another key', old.key;
  end if;
  return new;
end $$;
drop trigger if exists dashboards_keep_made on public.dashboards;
create trigger dashboards_keep_made before update on public.dashboards for each row execute function public.dashboards_keep_made();

-- Time moves "today" and "next" on its own: pg_cron redraws every minute
-- where it exists (Supabase); the local test run has none and skips it.
do $$
begin
  if to_regnamespace('cron') is not null then
    perform cron.unschedule(jobid) from cron.job where jobname = 'mcfly-dashboards';
    perform cron.schedule('mcfly-dashboards', '* * * * *', 'select public.render_made_dashboards()');
  end if;
end $$;

-- ───────────────────────────── Console ─────────────────────────────

-- What a board can pull from, for the console's pickers.
create or replace function public.admin_dashboard_sources()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return jsonb_build_object(
    'symbols', coalesce((select jsonb_agg(jsonb_build_object('symbol', s.symbol, 'name', coalesce(s.name, q.name), 'hidden', s.hidden)
                                          order by s.hidden, s.sort_order, s.symbol)
                           from public.symbols s left join public.quotes_latest q on q.symbol = s.symbol), '[]'),
    'metrics', coalesce((select jsonb_agg(jsonb_build_object('key', ms.key, 'label', coalesce(ms.label, l.label, ms.key), 'group', ms.group_name,
                                                             'unit', l.unit, 'hidden', ms.hidden)
                                          order by ms.hidden, ms.sort_order, ms.key)
                           from public.metric_settings ms left join public.metrics_latest l on l.key = ms.key), '[]'),
    'projects', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'status', p.status, 'agent_name', a.name)
                                           order by p.sort_order, p.name)
                            from public.projects p join public.agents a on a.id = p.agent_id), '[]'),
    'calendars', coalesce((select jsonb_agg(c.calendar order by c.calendar) from (select distinct e.calendar from public.events e) c), '[]'),
    'news_sections', coalesce((select jsonb_agg(jsonb_build_object('key', x.k, 'name', x.n) order by x.o, x.n)
                                 from (select i.section_key k, min(i.section_name) n, min(i.section_order) o
                                         from public.news_items i group by i.section_key) x), '[]'),
    'agents', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'color', a.color,
                                                            'has_key', exists (select 1 from public.agent_keys k where k.agent_id = a.id))
                                         order by a.name)
                          from public.agents a where a.revoked_at is null), '[]'),
    'timezone', public.dashboard_zone());
end $$;

-- A recipe the console may store: 1 to 20 known parts, each an object, with
-- lists where lists go. The drawing tolerates the rest.
create or replace function public.dashboard_check_sources(sources jsonb)
returns void
language plpgsql immutable set search_path = public as $$
declare
  part jsonb;
  k text;
begin
  if coalesce(jsonb_typeof(sources), 'null') <> 'array' or jsonb_array_length(sources) = 0 then
    raise exception 'a dashboard needs at least one part';
  end if;
  if jsonb_array_length(sources) > 20 then raise exception 'at most 20 parts on a dashboard'; end if;
  if octet_length(sources::text) > 40000 then raise exception 'this dashboard''s parts are too long'; end if;
  for part in select * from jsonb_array_elements(sources) loop
    if jsonb_typeof(part) <> 'object' then raise exception 'each part must be an object'; end if;
    if coalesce(part->>'from', '') not in ('quotes', 'metrics', 'projects', 'calendar', 'todos', 'news', 'brief', 'agents', 'note') then
      raise exception 'a part pulls from quotes, metrics, projects, calendar, todos, news, brief, agents or note (not %)', coalesce(part->>'from', 'nothing');
    end if;
    foreach k in array array['symbols', 'keys', 'projects', 'calendars', 'agents'] loop
      if part ? k and jsonb_typeof(part->k) <> 'array' then raise exception 'a part''s % must be a list', k; end if;
      if part ? k and jsonb_array_length(part->k) > 20 then raise exception 'at most 20 % in a part', k; end if;
    end loop;
    if part->>'from' = 'note' and btrim(coalesce(part->>'body', '')) = '' then raise exception 'a note needs some words'; end if;
  end loop;
end $$;

-- The board a recipe would draw, before it is saved.
create or replace function public.admin_preview_dashboard(sources jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  perform public.dashboard_check_sources(sources);
  return public.dashboard_widgets(sources);
end $$;

-- Makes a board (no id) or changes a made one. The key comes from the
-- title, made unique; it stays when the board is renamed.
create or replace function public.admin_save_dashboard(dashboard uuid, title text, sources jsonb,
                                                       subtitle text default null, template text default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  t text := left(btrim(coalesce(admin_save_dashboard.title, '')), 80);
  sub text := nullif(left(btrim(coalesce(admin_save_dashboard.subtitle, '')), 200), '');
  tpl text := nullif(btrim(coalesce(admin_save_dashboard.template, '')), '');
  base text;
  k text;
  n int := 1;
  saved uuid;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  if t = '' then raise exception 'give the dashboard a title'; end if;
  if tpl is not null and tpl !~ '^[a-z0-9][a-z0-9-]{0,39}$' then raise exception 'template % is not usable', tpl; end if;
  perform public.dashboard_check_sources(sources);
  if dashboard is null then
    if (select count(*) from public.dashboards d where d.sources is not null) >= 50 then raise exception 'at most 50 made dashboards'; end if;
    base := left(btrim(regexp_replace(lower(t), '[^a-z0-9]+', '-', 'g'), '-'), 56);
    if base = '' then base := 'board'; end if;
    k := base;
    while exists (select 1 from public.dashboards d where d.key = k) loop
      n := n + 1;
      k := base || '-' || n;
    end loop;
    insert into public.dashboards (agent_id, key, title, subtitle, template, sources, widgets)
    values (public.mcfly_agent(), k, t, sub, tpl, sources, public.dashboard_widgets(sources))
    returning id into saved;
    perform public.log_admin_action('create_dashboard', 'dashboard', saved::text, jsonb_strip_nulls(jsonb_build_object('key', k, 'template', tpl)));
  else
    update public.dashboards d
       set title = t, subtitle = sub, template = coalesce(tpl, d.template), sources = admin_save_dashboard.sources,
           widgets = public.dashboard_widgets(admin_save_dashboard.sources)
     where d.id = dashboard and d.sources is not null
    returning d.id into saved;
    if saved is null then
      if exists (select 1 from public.dashboards d where d.id = dashboard) then
        raise exception 'an agent lays this dashboard out; only a dashboard made here can be edited';
      end if;
      raise exception 'dashboard not found';
    end if;
    perform public.log_admin_action('edit_dashboard', 'dashboard', saved::text, jsonb_strip_nulls(jsonb_build_object('template', tpl)));
  end if;
  return saved;
end $$;

-- The list, now with each board's recipe (null for an agent's board).
drop function if exists public.admin_list_dashboards();
create function public.admin_list_dashboards()
returns table (id uuid, key text, title text, subtitle text, widgets jsonb, sort_order int, hidden boolean, updated_at timestamptz,
               agent_name text, agent_color text, template text, sources jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  return query
    select d.id, d.key, d.title, d.subtitle, d.widgets, d.sort_order, d.hidden, d.updated_at, a.name, a.color, d.template, d.sources
    from public.dashboards d join public.agents a on a.id = d.agent_id
    order by d.hidden, d.sort_order, d.title;
end $$;

revoke execute on function public.dashboard_zone() from public, anon, authenticated;
revoke execute on function public.dashboard_when(timestamptz, boolean, text) from public, anon, authenticated;
revoke execute on function public.dashboard_strings(jsonb, int) from public, anon, authenticated;
revoke execute on function public.dashboard_int(jsonb, int, int, int) from public, anon, authenticated;
revoke execute on function public.dashboard_waiting(text, text) from public, anon, authenticated;
revoke execute on function public.dashboard_part(jsonb, text) from public, anon, authenticated;
revoke execute on function public.dashboard_widgets(jsonb) from public, anon, authenticated;
revoke execute on function public.render_made_dashboards() from public, anon, authenticated;
revoke execute on function public.dashboards_redraw_soon() from public, anon, authenticated;
revoke execute on function public.dashboards_keep_made() from public, anon, authenticated;
revoke execute on function public.dashboard_check_sources(jsonb) from public, anon, authenticated;
revoke execute on function public.admin_dashboard_sources() from public, anon;
revoke execute on function public.admin_preview_dashboard(jsonb) from public, anon;
revoke execute on function public.admin_save_dashboard(uuid, text, jsonb, text, text) from public, anon;
revoke execute on function public.admin_list_dashboards() from public, anon;
grant execute on function public.admin_dashboard_sources() to authenticated;
grant execute on function public.admin_preview_dashboard(jsonb) to authenticated;
grant execute on function public.admin_save_dashboard(uuid, text, jsonb, text, text) to authenticated;
grant execute on function public.admin_list_dashboards() to authenticated;
