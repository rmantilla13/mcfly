-- The Supabase-only migrations: every feed table is in the realtime publication.
\set ON_ERROR_STOP 1
select tests.eq((select count(*)::int from pg_publication_tables where pubname = 'supabase_realtime'
                 and tablename in ('briefs', 'quotes', 'symbols', 'news_reports', 'news_items', 'platform_settings',
                                   'projects', 'project_updates', 'metrics', 'metric_settings', 'dashboards', 'events', 'todos')),
                13, 'feed tables are published');
