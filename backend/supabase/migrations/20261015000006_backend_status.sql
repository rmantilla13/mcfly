-- What the console's Settings → Backend shows: the newest migration applied,
-- the scheduled jobs, whether the scheduler's Vault values exist (never their
-- contents), and when calendars and bots last ran. Admin only.

create or replace function public.admin_backend_status()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  latest text;
  jobs jsonb;
  vault_ok jsonb;
begin
  if not public.is_platform_admin() then raise exception 'admin only'; end if;
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    execute 'select max(version) from supabase_migrations.schema_migrations' into latest;
  end if;
  if to_regnamespace('cron') is not null then
    execute $q$select coalesce(jsonb_agg(jsonb_build_object('name', jobname, 'schedule', schedule, 'active', active)
                                          order by jobname), '[]')
               from cron.job where jobname like 'mcfly-%'$q$ into jobs;
  end if;
  if to_regnamespace('vault') is not null then
    execute $q$select jsonb_build_object(
                 'project_url', exists (select 1 from vault.secrets where name = 'mcfly_project_url'),
                 'cron_secret', exists (select 1 from vault.secrets where name = 'mcfly_cron_secret'))$q$ into vault_ok;
  end if;
  return jsonb_build_object(
    'latest_migration', latest,
    'cron', jobs,
    'vault', vault_ok,
    'calendars', (select count(*) from public.calendar_sources),
    'last_calendar_sync', (select max(last_synced_at) from public.calendar_sources),
    'bots', (select count(*) from public.bots),
    'last_bot_run', (select max(last_run_at) from public.bots),
    'admins', (select count(*) from public.platform_admins),
    'displays', (select count(*) from public.devices));
end $$;
revoke execute on function public.admin_backend_status() from public, anon;
grant execute on function public.admin_backend_status() to authenticated;
