-- The scheduler's secret never leaves the database: pg_cron sends it (from
-- Vault, 20261015000003 and 20261015000005) and the functions ask here
-- whether a caller's matches, instead of keeping their own copy. Service
-- role only. (A MCFLY_CRON_SECRET function secret, if set, also works.)

create or replace function public.cron_secret_matches(candidate text)
returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  secret text;
begin
  if candidate is null or length(candidate) < 32 or to_regnamespace('vault') is null then
    return false;
  end if;
  execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'mcfly_cron_secret'$q$ into secret;
  return secret is not null and secret = candidate;
end $$;
revoke execute on function public.cron_secret_matches(text) from public, anon, authenticated;
