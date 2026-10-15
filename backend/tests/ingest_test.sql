-- The ingest functions behind the ingest edge function: briefs, quotes and
-- Daily Pulse reports, called with the service role.
\set ON_ERROR_STOP 1
\set grok   '00000000-0000-0000-0000-00000000a001'
\set stocks '00000000-0000-0000-0000-00000000a002'
\set pulse  '00000000-0000-0000-0000-00000000a003'
select tests.login_service();

-- ───────────────────────────── Briefs ─────────────────────────────
select tests.eq(ingest_briefs(:'grok', '[{"id": "h-9", "title": " Nine o''clock ", "body": "Quiet.", "kind": "hourly", "published_at": "2026-10-14T14:00:00Z"}]'), 1, 'one brief');
select tests.eq((select title from briefs where external_id = 'h-9'), 'Nine o''clock', 'title is trimmed');
select tests.eq((select published_at from briefs where external_id = 'h-9'), '2026-10-14T14:00:00Z'::timestamptz, 'published_at is taken');
select tests.eq(ingest_briefs(:'grok', '[{"id": "h-9", "title": "Nine, revised", "body": "Busier."}]'), 1, 'same id again');
select tests.eq((select count(*)::int from briefs where external_id = 'h-9'), 1, 'a re-push replaces the brief');
select tests.eq((select row(title, body, kind)::text from briefs where external_id = 'h-9'), row('Nine, revised', 'Busier.', 'update')::text, 'replaced fields');
select tests.eq(ingest_briefs(:'grok', '[{"title": "no id"}, {"title": "no id"}]'), 2, 'briefs without an id are separate rows');
select tests.eq((select count(*)::int from briefs where title = 'no id'), 2, 'both landed');
select tests.eq((select published_at > now() - interval '1 minute' from briefs where title = 'no id' limit 1), true, 'published_at defaults to now');
select tests.eq((select published_at from briefs where external_id = 'bad-time'), null, 'no row yet');
select tests.eq(ingest_briefs(:'grok', '[{"id": "bad-time", "title": "t", "published_at": "yesterday-ish"}]'), 1, 'an unreadable time is accepted');
select tests.ok((select published_at > now() - interval '1 minute' from briefs where external_id = 'bad-time'), 'and falls back to now');
select tests.throws($$select ingest_briefs('00000000-0000-0000-0000-00000000a001', '{"title": "x"}')$$, 'briefs must be a list', 'not a list');
select tests.throws($$select ingest_briefs('00000000-0000-0000-0000-00000000a001', '["x"]')$$, 'each brief must be an object', 'not objects');
select tests.throws($$select ingest_briefs('00000000-0000-0000-0000-00000000a001', '[{"body": "no title"}]')$$, '%null value%', 'title is required');
select tests.throws($$select ingest_briefs('00000000-0000-0000-0000-00000000a001', '[{"title": "x", "kind": "weekly"}]')$$, 'kind must be%', 'unknown kind');
select tests.throws($$select ingest_briefs('00000000-0000-0000-0000-00000000a001', '[{"title": ""}]')$$, '%check constraint%', 'empty title');
select tests.throws($$select ingest_briefs('00000000-0000-0000-0000-00000000a001', (select jsonb_agg(jsonb_build_object('title', 't')) from generate_series(1, 201)))$$,
                    'at most 200 briefs per push', 'too many');

-- ───────────────────────────── Quotes ─────────────────────────────
select tests.eq(ingest_quotes(:'stocks', '[{"symbol": "aapl", "name": "Apple", "price": 250.5, "change": 2.6, "change_pct": 1.05, "note": "Up on services."},
                                          {"symbol": "BRK.B", "price": "495.12", "currency": "usd"},
                                          {"symbol": "^GSPC", "name": "S&P 500", "price": 6700}]',
                              '2027-01-01T20:00:00Z'), 3, 'three quotes');
select tests.eq((select row(symbol, price, change, currency, note)::text from quotes_latest where symbol = 'AAPL'),
                row('AAPL', 250.5::numeric, 2.6::numeric, 'USD', 'Up on services.')::text, 'AAPL is the newest');
select tests.eq((select as_of from quotes_latest where symbol = 'BRK.B'), '2027-01-01T20:00:00Z'::timestamptz, 'as_of comes from the push');
select tests.eq((select currency from quotes_latest where symbol = 'BRK.B'), 'USD', 'currency is upper-cased');
select tests.eq((select count(*)::int from quotes where symbol = 'AAPL'), 3, 'history keeps growing');
select tests.eq((select name from symbols where symbol = '^GSPC'), 'S&P 500', 'a new symbol is listed');
select tests.eq((select sort_order from symbols where symbol = '^GSPC'), 1000, 'new symbols sort last');
select tests.eq(ingest_quotes(:'stocks', '[{"symbol": "AAPL", "price": 1, "as_of": "2027-01-01T21:00:00Z"}]'), 1, 'one more');
select tests.eq((select name from symbols where symbol = 'AAPL'), 'Apple', 'a push without a name keeps the old one');
select tests.eq((select price from quotes_latest where symbol = 'AAPL'), 1::numeric, 'the newest as_of wins');
select tests.throws($$select ingest_quotes('00000000-0000-0000-0000-00000000a002', '[{"symbol": "no price"}]')$$, 'symbol % is not usable', 'bad symbol');
select tests.throws($$select ingest_quotes('00000000-0000-0000-0000-00000000a002', '[{"symbol": "MSFT"}]')$$, 'quote MSFT has no price', 'missing price');
select tests.throws($$select ingest_quotes('00000000-0000-0000-0000-00000000a002', '[{"symbol": "MSFT", "price": "lots"}]')$$, '%invalid input syntax%', 'non-numeric price');
select tests.throws($$select ingest_quotes('00000000-0000-0000-0000-00000000a002', '{"symbol": "MSFT", "price": 1}')$$, 'quotes must be a list', 'not a list');

-- ───────────────────────────── News ─────────────────────────────
select ingest_news(:'pulse', '{"date": "Oct 15, 2026", "slug": "2026-10-15", "hero": "two",
  "sections": [{"key": "i", "name": "AI Tech", "items": [
     {"id": "one", "h": "First story", "t": "Why it matters.", "url": "https://www.example.com/a?x=1"},
     {"id": "two", "h": "Second story", "t": "Also matters.", "url": "https://blog.google/path", "image": "https://img.example.com/2.jpg"}]},
   {"key": "s", "name": "Social", "items": [{"h": "No id here", "url": "https://x.com/post/1"}]}]}') as report \gset
select tests.eq((select row(slug, report_date, display_date, hero_item)::text from news_reports where id = :'report'),
                row('2026-10-15', '2026-10-15'::date, 'Oct 15, 2026', 'two')::text, 'report header');
select tests.eq((select count(*)::int from news_items where report_id = :'report'), 3, 'three items');
select tests.eq((select row(section_order, position, source_domain, image_url)::text from news_items where report_id = :'report' and item_key = 'one'),
                row(0, 0, 'example.com', null)::text, 'first item: www stripped, no image');
select tests.eq((select row(section_order, position, source_domain, image_url)::text from news_items where report_id = :'report' and item_key = 'two'),
                row(0, 1, 'blog.google', 'https://img.example.com/2.jpg')::text, 'second item keeps its image');
select tests.eq((select row(item_key, takeaway, section_name)::text from news_items where report_id = :'report' and section_key = 's'),
                row('item-1-0', '', 'Social')::text, 'an item without an id or takeaway gets defaults');

-- The same slug again replaces the report.
select ingest_news(:'pulse', '{"date": "Oct 15, 2026", "slug": "2026-10-15",
  "sections": [{"key": "a", "name": "Ads", "items": [{"id": "x", "h": "Only story", "t": "", "url": "https://adweek.com/x"}]}]}') as report2 \gset
select tests.eq((select count(*)::int from news_reports where slug = '2026-10-15'), 1, 'one report per slug');
select tests.ok(:'report' <> :'report2', 'a new row');
select tests.eq((select count(*)::int from news_items where report_id = :'report'), 0, 'old items are gone');
select tests.eq((select count(*)::int from news_items where report_id = :'report2'), 1, 'new items are in');

-- Validation.
select tests.throws($$select ingest_news('00000000-0000-0000-0000-00000000a003', '{"slug": "Bad Slug", "sections": [{"key": "a", "name": "A", "items": [{"h": "x", "url": "https://a.b"}]}]}')$$,
                    'slug must be like 2026-10-14', 'bad slug');
select tests.throws($$select ingest_news('00000000-0000-0000-0000-00000000a003', '{"slug": "2026-10-16", "sections": []}')$$,
                    'sections must be a non-empty list', 'no sections');
select tests.throws($$select ingest_news('00000000-0000-0000-0000-00000000a003', '{"slug": "2026-10-16", "sections": [{"key": "a", "name": "A", "items": []}]}')$$,
                    'the report has no items', 'no items');
select tests.throws($$select ingest_news('00000000-0000-0000-0000-00000000a003', '{"slug": "2026-10-16", "sections": [{"key": "a", "name": "A", "items": [{"h": "x", "url": "ftp://a.b"}]}]}')$$,
                    '%check constraint%', 'a story needs an http(s) link');
select tests.throws($$select ingest_news('00000000-0000-0000-0000-00000000a003', '{"slug": "2026-10-16", "sections": [{"key": "a", "name": "A", "items": [{"url": "https://a.b"}]}]}')$$,
                    '%null value%', 'a story needs a headline');
select tests.eq((select count(*)::int from news_reports where slug = '2026-10-16'), 0, 'a failed report leaves nothing behind');
-- A slug that is not a date still gets a date.
select ingest_news(:'pulse', '{"slug": "special-edition", "sections": [{"key": "a", "name": "A", "items": [{"h": "x", "url": "https://a.b"}]}]}') as special \gset
select tests.eq((select report_date from news_reports where id = :'special'), current_date, 'report_date defaults to today');

-- ───────────────────────── Log and retention ─────────────────────────
select tests.logout();
update agents set last_seen_at = null where id = :'grok';
select tests.login_service();
select tests.eq((select last_seen_at from agents where id = :'grok'), null, 'not seen yet');
select record_ingest(:'grok', 'briefs', 3, 'ok');
select tests.ok((select last_seen_at > now() - interval '1 minute' from agents where id = :'grok'), 'a push marks the agent seen');
select record_ingest(:'grok', 'briefs', 0, 'error', 'kind must be hourly, daily, alert or update');
select tests.eq((select count(*)::int from ingest_log where agent_id = :'grok'), 3, 'both logged (plus the seed row)');
select tests.eq((select message from admin_list_ingest(1, 0)), 'kind must be hourly, daily, alert or update', 'newest first');

select tests.logout();
update briefs set published_at = now() - interval '40 days' where title = 'no id';
update quotes set as_of = now() - interval '100 days' where symbol = 'NVDA';
insert into news_reports (agent_id, slug, report_date) select :'pulse', 'old-' || g, current_date - 100 - g from generate_series(1, 20) g;
insert into ingest_log (agent_id, feed, created_at) values (:'grok', 'briefs', now() - interval '100 days');
select tests.login_service();
select prune_feed() as pruned \gset
select tests.eq((:'pruned')::jsonb - 'metrics' - 'events' - 'updates', '{"briefs": 2, "quotes": 1, "reports": 9, "log": 1}'::jsonb, 'retention: 30 days of briefs, 90 of quotes, 14 reports');
select tests.eq((select count(*)::int from quotes where symbol = 'NVDA'), 1, 'the newest quote of a symbol always stays');
select tests.eq((select count(*)::int from news_reports), 14, '14 reports kept');
select tests.ok(exists (select 1 from news_reports where slug = '2026-10-15'), 'the newest report is among them');
