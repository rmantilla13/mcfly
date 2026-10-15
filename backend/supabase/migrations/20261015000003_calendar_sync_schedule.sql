-- Every 15 minutes, pg_cron asks the calendar-sync function to read each
-- calendar subscription (20261015000002). The call carries a shared secret
-- the function checks, because the functions skip the gateway's JWT check.
--
-- Both values live in Supabase Vault, set once after deploying:
--   select vault.create_secret('https://<ref>.supabase.co', 'mcfly_project_url');
--   select vault.create_secret('<random>', 'mcfly_cron_secret');
-- and the same secret as the functions' MCFLY_CRON_SECRET. Until both are
-- there, the tick does nothing.
--
-- Guarded so a Postgres without pg_cron / pg_net (the local test run) skips
-- the schedule and keeps everything else.

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_net with schema extensions;
  end if;
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
  end if;
end $$;

create or replace function public.calendar_sync_tick()
returns void
language plpgsql security definer set search_path = public as $$
declare
  base text;
  secret text;
begin
  if to_regnamespace('vault') is null or to_regnamespace('net') is null then
    return;
  end if;
  execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'mcfly_project_url'$q$ into base;
  execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'mcfly_cron_secret'$q$ into secret;
  if base is null or secret is null then
    return;
  end if;
  execute $q$select net.http_post(url := $1, headers := $2, body := '{}'::jsonb, timeout_milliseconds := 60000)$q$
    using rtrim(base, '/') || '/functions/v1/calendar-sync',
          jsonb_build_object('Content-Type', 'application/json', 'x-mcfly-cron', secret);
end $$;
revoke execute on function public.calendar_sync_tick() from public, anon, authenticated;

do $$
begin
  if to_regnamespace('cron') is not null then
    perform cron.unschedule(jobid) from cron.job where jobname = 'mcfly-calendar-sync';
    perform cron.schedule('mcfly-calendar-sync', '*/15 * * * *', 'select public.calendar_sync_tick()');
  end if;
end $$;
