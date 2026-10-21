-- The articles behind the news stories, read when someone opens one. The
-- `article` edge function fetches a story's page the first time it is opened,
-- keeps its text, pictures and videos as blocks with a short summary, and
-- every display and the app read this copy after that. One row per story: it
-- goes with its item, so a report pushed again is read afresh.
--
--   status        ready        the page's own text
--                 partial      only what the page says about itself (a paywall, a video)
--                 unavailable  nothing usable; clients keep the takeaway and the link
--   blocks        [{ type: p | h | quote | list | image | video, ... }] in page order
--                 (docs/PLATFORM_SPEC.md has the shapes)
--   summary       a few sentences; points: the key points; summary_model: who wrote them
--   summary_tried_at  the last attempt, so a model that's down isn't asked on every open

create table public.news_articles (
  item_id           uuid primary key references public.news_items on delete cascade,
  status            text not null check (status in ('ready', 'partial', 'unavailable')),
  title             text check (length(title) <= 300),
  byline            text check (length(byline) <= 200),
  site_name         text check (length(site_name) <= 120),
  published_at      timestamptz,
  lead_image        text check (lead_image is null or lead_image ~* '^https?://'),
  blocks            jsonb not null default '[]' check (jsonb_typeof(blocks) = 'array'),
  word_count        int not null default 0 check (word_count >= 0),
  summary           text check (length(summary) <= 2000),
  points            jsonb not null default '[]' check (jsonb_typeof(points) = 'array'),
  summary_model     text check (length(summary_model) <= 80),
  summary_tried_at  timestamptz,
  fetched_at        timestamptz not null default now()
);

alter table public.news_articles enable row level security;
create policy news_articles_read on public.news_articles for select using (public.can_read());
revoke insert, update, delete on public.news_articles from anon, authenticated;

-- Writes one article, checked again here: the edge function (service role)
-- is the only caller.
create function public.store_news_article(item uuid, article jsonb)
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
                                         word_count, summary, points, summary_model, summary_tried_at, fetched_at)
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
          public.read_timestamp(article->'fetched_at', now()))
  on conflict (item_id) do update set
    status = excluded.status, title = excluded.title, byline = excluded.byline, site_name = excluded.site_name,
    published_at = excluded.published_at, lead_image = excluded.lead_image, blocks = excluded.blocks,
    word_count = excluded.word_count, summary = excluded.summary, points = excluded.points,
    summary_model = excluded.summary_model, summary_tried_at = excluded.summary_tried_at, fetched_at = excluded.fetched_at;
end $$;

revoke execute on function public.store_news_article(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.store_news_article(uuid, jsonb) to service_role;
