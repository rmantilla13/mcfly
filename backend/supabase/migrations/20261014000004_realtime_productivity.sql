-- Supabase-only: the productivity tables join the realtime publication.
alter publication supabase_realtime add table
  public.projects,
  public.project_updates,
  public.metrics,
  public.metric_settings,
  public.dashboards,
  public.events;
