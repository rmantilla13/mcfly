-- Supabase-only: asks join the realtime publication with the other feeds, so
-- an answer on one screen reaches the others at once.
alter publication supabase_realtime add table public.asks;
