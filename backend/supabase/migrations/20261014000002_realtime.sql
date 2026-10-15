-- Supabase-only setup: the tables displays may subscribe to for live
-- updates. (The display polls every minute today; this is for later.)
alter publication supabase_realtime add table
  public.briefs,
  public.quotes,
  public.symbols,
  public.news_reports,
  public.news_items,
  public.platform_settings;
