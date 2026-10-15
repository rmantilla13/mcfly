# From the Daily Pulse handoff to McFly

The Daily Pulse pipeline (the `HANDOFF.pdf` of October 14, 2026) produces,
every morning at 8:06 CT, `items-YYYY-MM-DD.json` plus a one-pager PNG, a
vertical MP4 and a GIF, on the agent box, with nothing served anywhere and
no device to show it on. The handoff proposed a Raspberry Pi 5 kiosk and a
sync step. McFly is that, and more.

## What maps to what

| Handoff | McFly |
|---|---|
| `items-YYYY-MM-DD.json` (date, slug, hero, sections → items with `id`, `h`, `t`, `url`, `image`) | Pushed as is to `POST /ingest/news` ([AGENTS.md](AGENTS.md)); stored as `news_reports` + `news_items`; a re-push with the same slug replaces the day |
| "How images are chosen" (item image → YouTube thumbnail → og:image → branded graphic) | The same order, done by the `ingest` function for items without `image`; the display draws a tinted section tile when there is none |
| Proposed kiosk web UI (Chromium, latest.json, tap targets ≥ 48 px, detail view with a QR code for the link) | The Qt kiosk's News screen: section headers, story cards, a detail view with the picture, the takeaway, the source and a QR code; 64 px targets |
| Idle screensaver looping the MP4 | The Headlines screen saver: today's stories one at a time with a slow zoom on their pictures, cross-fading every 12 s |
| Daily sync (static host + cron, rsync, Syncthing) | None needed: the pipeline pushes to Supabase, every display and the phone read it within a minute |
| Display choice (7" 800×480, Touch Display 2 720×1280, any HDMI monitor) | The 10.1" 1920×1200 panel at `QT_SCALE_FACTOR=1.5` (the Ohana hardware); other sizes through `--size` and the layout tiers (`display/docs/LAYOUTS.md`) |

## Running the pipeline against McFly

After `python3 pipeline.py items-2026-10-14.json`, one more line:

```bash
MCFLY_URL=https://<project>.supabase.co MCFLY_KEY=mcf_… \
  python3 scripts/mcfly_push.py news items-2026-10-14.json
```

(or `curl -X POST … -d @items-2026-10-14.json`, as in AGENTS.md). The
pipeline's own images can be sent along in each item's `image` field, which
skips the og:image lookup; without them McFly looks the pictures up itself.
The PNG, MP4 and GIF stay useful for chat and sharing; the display does not
use them.

## Still open from the handoff

- Two stories that share a source still get the same picture.
- No source video: the motion on the display is the Ken Burns zoom, as in
  the MP4.
- The 8:06 schedule stays in the chat agent; the push is one extra step at
  the end of the pipeline.
