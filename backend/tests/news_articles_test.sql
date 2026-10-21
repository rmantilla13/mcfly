-- The articles behind the stories: only the edge function (service role)
-- writes them, through store_news_article; whoever can read the feeds reads
-- them; they go with their story.
\set ON_ERROR_STOP 1
\set device   'd0000000-0000-0000-0000-000000000001'
\set stranger 'e0000000-0000-0000-0000-000000000001'
\set admin    'ad000000-0000-0000-0000-000000000001'

insert into auth.users (id, email, raw_app_meta_data) values
  (:'admin', 'admin@example.com', '{}'),
  (:'device', 'device-1@devices.mcfly.invalid', '{"kind": "device"}'),
  (:'stranger', 'stranger@example.com', '{}');
insert into devices (id, user_id, name) values ('00000000-0000-0000-0000-00000000d001', :'device', 'Kitchen');

select id as item from news_items where item_key = 'claude' \gset
select id as other from news_items where item_key = 'tiktok' \gset

-- ───────────────────────────── Writing ─────────────────────────────
select tests.login_service();
select store_news_article(:'item', $j${
  "status": "ready", "title": "  Claude 5 for everyone  ", "byline": "A. Writer", "site_name": "Anthropic",
  "published_at": "2026-10-20T14:00:00Z", "lead_image": "https://cdn.example.com/lead.jpg",
  "blocks": [
    { "type": "p", "text": "First paragraph." },
    { "type": "image", "url": "https://cdn.example.com/1.jpg", "caption": "A chart" },
    { "type": "video", "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "provider": "youtube" },
    { "type": "list", "items": ["one", "two"] }
  ],
  "word_count": 640, "summary": "It ships.", "points": ["One", "Two"], "summary_model": "claude-sonnet-5-5",
  "summary_tried_at": "2026-10-21T08:00:00Z"
}$j$::jsonb);
select tests.eq((select title from news_articles where item_id = :'item'), 'Claude 5 for everyone', 'title is trimmed');
select tests.eq((select jsonb_array_length(blocks) from news_articles where item_id = :'item'), 4, 'blocks are kept');
select tests.eq((select word_count from news_articles where item_id = :'item'), 640, 'word count is kept');
select tests.eq((select published_at from news_articles where item_id = :'item'), '2026-10-20T14:00:00Z'::timestamptz, 'published time is read');

-- Grok's picture is kept with the article.
select store_news_article(:'item', '{"status": "ready", "illustration": "x.jpg", "illustration_model": "grok-imagine-image-2.0", "illustration_tried_at": "2026-10-21T08:00:00Z"}');
select tests.eq((select illustration from news_articles where item_id = :'item'), 'x.jpg', 'the picture''s path is kept');
select tests.eq((select illustration_model from news_articles where item_id = :'item'), 'grok-imagine-image-2.0', 'and who drew it');
select tests.throws($$select store_news_article('$$ || :'other' || $$', '{"status": "ready", "illustration": "../../etc/passwd x"}')$$,
                    '%news_articles_illustration_check%', 'a picture path with a space');
select tests.eq((select count(*)::int from orphaned_illustrations()), 0, 'no storage here: no orphans');

-- A second write replaces the first.
select store_news_article(:'item', '{"status": "partial", "blocks": [{"type": "p", "text": "Teaser."}], "summary": null}');
select tests.eq((select status from news_articles where item_id = :'item'), 'partial', 'a second write replaces the row');
select tests.ok((select summary is null and title is null from news_articles where item_id = :'item'), 'replaced fields are cleared');
select tests.eq((select count(*)::int from news_articles), 1, 'still one row per story');

-- Payloads the function refuses.
select tests.throws($$select store_news_article('$$ || :'other' || $$', '{"status": "sideways"}')$$, '%news_articles_status_check%', 'an unknown status');
select tests.throws($$select store_news_article('$$ || :'other' || $$', '{"status": "ready", "blocks": [{"type": "script"}]}')$$,
                    'each block needs a type%', 'an unknown block type');
select tests.throws($$select store_news_article('$$ || :'other' || $$', '{"status": "ready", "blocks": [{"type": "image", "url": "javascript:alert(1)"}]}')$$,
                    'an image block needs an http(s) url', 'a picture without an http url');
select tests.throws($$select store_news_article('$$ || :'other' || $$', '{"status": "ready", "lead_image": "data:x"}')$$,
                    '%news_articles_lead_image_check%', 'a lead image that is not http');
select tests.throws($$select store_news_article('$$ || :'other' || $$', '{"status": "ready", "blocks": {}}')$$, 'blocks must be a list', 'blocks as an object');
select tests.throws($$select store_news_article('00000000-0000-0000-0000-000000000000', '{"status": "ready"}')$$,
                    '%foreign key%', 'a story that does not exist');

-- ───────────────────────────── Reading ─────────────────────────────
select tests.login(null);
select tests.eq((select count(*)::int from news_articles), 0, 'anon sees no articles');
select tests.throws($$select store_news_article('$$ || :'other' || $$', '{"status": "ready"}')$$, 'permission denied%', 'anon cannot write');

select tests.login(:'stranger');
select tests.eq((select count(*)::int from news_articles), 0, 'a stranger sees no articles');

select tests.login(:'device');
select tests.eq((select count(*)::int from news_articles), 1, 'a display reads articles');
select tests.throws($$select store_news_article('$$ || :'other' || $$', '{"status": "ready"}')$$, 'permission denied%', 'a display cannot call the writer');
select tests.throws($$insert into news_articles (item_id, status) values ('$$ || :'other' || $$', 'ready')$$,
                    'permission denied%', 'a display cannot insert');
select tests.throws($$delete from news_articles$$, 'permission denied%', 'a display cannot delete');

select tests.login(:'admin');
select tests.eq((select count(*)::int from news_articles), 1, 'the admin reads articles');
select tests.throws($$select orphaned_illustrations()$$, 'permission denied%', 'the admin cannot list stored pictures');
select tests.throws($$select store_news_article('$$ || :'other' || $$', '{"status": "ready"}')$$, 'permission denied%', 'the admin cannot call the writer');

-- ───────────────────────────── Lifetime ─────────────────────────────
select tests.logout();
delete from news_reports;
select tests.eq((select count(*)::int from news_articles), 0, 'articles go with their report');
