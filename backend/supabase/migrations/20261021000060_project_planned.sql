-- A project can be planned: lined up but not started. The console, the
-- display and the app list planned projects as "Up next", after the ones in
-- flight (active, blocked, paused) and before the done ones. An agent says
-- so with "status": "planned"; nothing else about a project changes.

alter table public.projects drop constraint projects_status_check;
alter table public.projects
  add constraint projects_status_check check (status in ('planned', 'active', 'blocked', 'paused', 'done'));
