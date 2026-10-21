-- A picture Grok draws for each opened story, shown with its summary. The
-- `article` function asks xAI's image model the first time a story is opened,
-- keeps the picture in the private `news-illustrations` bucket under
-- <item_id>.jpg and answers with a signed link to it.
--
--   illustration          the object's path in the bucket
--   illustration_model    the model that drew it
--   illustration_tried_at the last attempt, so a refusal isn't asked again on every open
--
-- store_news_article is restated whole (20261021000010) to keep them.

alter table public.news_articles
  add column if not exists illustration text check (illustration ~ '^[A-Za-z0-9._/-]{1,200}$'),
  add column if not exists illustration_model text check (length(illustration_model) <= 80),
  add column if not exists illustration_tried_at timestamptz;

create or replace function public.store_news_article(item uuid, article jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare
  b jsonb;
  kinds constant text[] := array['p', 'h', 'quote', 'list', 'image', 'video'];
begin
  if jsonb_typeof(article) <> 'object' then raise exception 'the article must be an object'; end if;
  if coalesce(jsonb_typeof(article->'blocks'), 'array') <> 'array' then raise exception 'blocks must be a list'; end if;
  if coalesce(jsonb_typeof(article->'points'), 'array') <> 'array' then raise exception 'points must be a list'; end if;
  if jsonb_array_length(coalesce(article->'blocks', '[]')) > 400 then raise exception 'at most 400 blocks'; end if;
  if jsonb_array_length(coalesce(article->'points', '[]')) > 8 then raise exception 'at most 8 points'; end if;
  if pg_column_size(article) > 1024 * 1024 then raise exception 'the article is over 1 MB'; end if;
  for b in select * from jsonb_array_elements(coalesce(article->'blocks', '[]')) loop
    if jsonb_typeof(b) <> 'object' or not (b->>'type' = any (kinds)) then
      raise exception 'each block needs a type: p, h, quote, list, image or video';
    end if;
    if b->>'type' in ('image', 'video') and coalesce(b->>'url', '') !~* '^https?://' then
      raise exception 'an % block needs an http(s) url', b->>'type';
    end if;
  end loop;

  insert into public.news_articles as a (item_id, status, title, byline, site_name, published_at, lead_image, blocks,
                                         word_count, summary, points, summary_model, summary_tried_at,
                                         illustration, illustration_model, illustration_tried_at, fetched_at)
  values (item,
          article->>'status',
          left(nullif(btrim(article->>'title'), ''), 300),
          left(nullif(btrim(article->>'byline'), ''), 200),
          left(nullif(btrim(article->>'site_name'), ''), 120),
          public.read_timestamp(article->'published_at', null),
          nullif(btrim(article->>'lead_image'), ''),
          coalesce(article->'blocks', '[]'),
          greatest(0, coalesce((article->>'word_count')::int, 0)),
          left(nullif(btrim(article->>'summary'), ''), 2000),
          coalesce(article->'points', '[]'),
          left(nullif(btrim(article->>'summary_model'), ''), 80),
          public.read_timestamp(article->'summary_tried_at', null),
          nullif(btrim(article->>'illustration'), ''),
          left(nullif(btrim(article->>'illustration_model'), ''), 80),
          public.read_timestamp(article->'illustration_tried_at', null),
          public.read_timestamp(article->'fetched_at', now()))
  on conflict (item_id) do update set
    status = excluded.status, title = excluded.title, byline = excluded.byline, site_name = excluded.site_name,
    published_at = excluded.published_at, lead_image = excluded.lead_image, blocks = excluded.blocks,
    word_count = excluded.word_count, summary = excluded.summary, points = excluded.points,
    summary_model = excluded.summary_model, summary_tried_at = excluded.summary_tried_at,
    illustration = excluded.illustration, illustration_model = excluded.illustration_model,
    illustration_tried_at = excluded.illustration_tried_at, fetched_at = excluded.fetched_at;
end $$;

revoke execute on function public.store_news_article(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.store_news_article(uuid, jsonb) to service_role;

-- Pictures whose story is gone (a report pruned, deleted or pushed again):
-- the function removes them through the Storage API after it draws a new one.
create or replace function public.orphaned_illustrations(lim int default 100)
returns setof text
language plpgsql stable security definer set search_path = public as $$
begin
  if to_regclass('storage.objects') is null then return; end if;
  return query execute
    'select o.name from storage.objects o
      where o.bucket_id = ''news-illustrations''
        and not exists (select 1 from public.news_articles a where a.illustration = o.name)
      order by o.created_at limit $1'
    using lim;
end $$;

revoke execute on function public.orphaned_illustrations(int) from public, anon, authenticated;
grant execute on function public.orphaned_illustrations(int) to service_role;

-- The bucket: private, read through signed links the function makes. Plain
-- Postgres (the tests) has no storage schema.
do $$
begin
  if to_regclass('storage.buckets') is not null then
    execute $q$insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
               values ('news-illustrations', 'news-illustrations', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
               on conflict (id) do nothing$q$;
  end if;
end $$;
