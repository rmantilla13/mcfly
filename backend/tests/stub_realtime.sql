-- Just enough of Supabase Realtime to apply 20261014000002_realtime.sql on
-- plain Postgres. Loaded after stub_auth.sql.
set client_min_messages = error;
create publication supabase_realtime;
reset client_min_messages;
