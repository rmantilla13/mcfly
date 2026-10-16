-- Supabase-only: todos join the realtime publication with the other feeds.
alter publication supabase_realtime add table public.todos;
