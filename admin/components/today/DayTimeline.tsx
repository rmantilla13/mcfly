"use client";

import { cn } from "cn";
import { CalendarIcon, CalendarDaysIcon, CircleAlertIcon, FileTextIcon, GitCommitHorizontalIcon, NewspaperIcon, ZapIcon } from "lucide-react";
import Link from "next/link";
import { useEffect, useLayoutEffect, useRef } from "react";
import { cssColor } from "@/lib/format";
import { focusIndex, nowPosition, rowState, tomorrowLabel, untilLabel, type TimelineItem } from "@/lib/today";
import { Tile, TileHead } from "./Tile";
import styles from "./today.module.css";

// The day, as one stream in time order (lib/today.ts buildTimeline): what
// arrived and what is planned, on a rail. A line marks now: it sits between
// the rows by the clock (a third of the way from the 9:00 row to the 12:00
// row at 10:00) and glides there when the minute turns, and the rail above
// it fills in. While it crosses a row only its dot shows, on the rail. The list keeps "now" in view, one row of context above,
// until someone scrolls it. Under the day's last row, tomorrow's events
// preview what's coming, on the same rows.

const KIND_ICON = { news: NewspaperIcon, brief: FileTextIcon, alert: CircleAlertIcon, project: GitCommitHorizontalIcon, event: CalendarIcon };
// Keys that scroll the list when focus is inside it: someone reading it.
const SCROLL_KEYS = new Set(["ArrowUp", "ArrowDown", "PageUp", "PageDown", "Home", "End", " "]);
const GAP = 10; // between rows (gap-2.5); the line sits in the middle of it
const RAIL_X = 76; // the rail's centre: the time column (56) + gap (8) + half the rail column (12)
const RAIL_TOP = 12; // where the rail starts (top-3)
const DOT = 12; // the now dot (size-3)
const ARM = "transition-opacity duration-500 group-data-[over=true]:opacity-0 motion-reduce:transition-none";

export function DayTimeline({
  items,
  tomorrow,
  now,
  timeZone,
  index,
  className,
}: {
  items: TimelineItem[];
  tomorrow: TimelineItem[];
  now: number;
  timeZone: string;
  index: number;
  className?: string;
}) {
  return (
    <Tile index={index} label="Your day" className={cn("gap-3 py-5 pr-2 pl-3", className)}>
      <TileHead icon={<CalendarDaysIcon />} className="pr-3 pl-2" action={<span className="text-xs text-muted-foreground">{items.length === 1 ? "1 thing" : `${items.length} things`}</span>}>
        Your day
      </TileHead>
      {items.length === 0 ? (
        <p className="px-2 pb-2 text-[15px] text-muted-foreground">
          Nothing yet today. Briefs, the Pulse, project updates and your calendar land here as your agents push them.
        </p>
      ) : null}
      {items.length > 0 || tomorrow.length > 0 ? <DayRail items={items} tomorrow={tomorrow} now={now} timeZone={timeZone} /> : null}
    </Tile>
  );
}

function DayRail({ items, tomorrow, now, timeZone }: { items: TimelineItem[]; tomorrow: TimelineItem[]; now: number; timeZone: string }) {
  const scroller = useRef<HTMLDivElement>(null);
  const track = useRef<HTMLDivElement>(null);
  const line = useRef<HTMLDivElement>(null);
  const fill = useRef<HTMLSpanElement>(null);
  const after = useRef<HTMLDivElement>(null); // where tomorrow starts: the end of today's rows
  const touched = useRef(false);
  const placed = useRef(false);
  const shown = useRef(false); // the line is up; until it is, it's placed without gliding
  const lastY = useRef(-1);
  const focus = Math.max(0, focusIndex(items, now) - 1);
  const { from, to, f } = nowPosition(items, now);
  const layout = [...items, ...tomorrow].map((i) => i.key).join("|");

  // Keep "now" in view, one row of context above, until someone scrolls:
  // straight there when the page opens, gliding when the day moves on
  // (unless motion is turned down).
  useEffect(() => {
    const box = scroller.current;
    const row = track.current?.querySelectorAll<HTMLElement>("[data-row]")[focus];
    if (!box || !row || touched.current) return;
    const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    box.scrollTo({ top: row.offsetTop - 4, behavior: placed.current && !still ? "smooth" : "instant" });
    placed.current = true;
  }, [focus]);

  // The line's place is measured (rows are as tall as their text) and
  // written straight to it, so a new minute moves it without a render. The
  // server can't measure, so it starts hidden; the first time, it is put in
  // place with nothing moving and fades in there, and from then on it glides.
  useLayoutEffect(() => {
    const box = track.current;
    if (!box) return;
    const place = () => {
      const mark = line.current;
      const lived = fill.current;
      if (!mark || !lived) return;
      const rows = box.querySelectorAll<HTMLElement>("[data-row]");
      if (rows.length === 0) {
        // Nothing today: no line to place, and no part of the rail lived.
        mark.style.opacity = "0";
        lived.style.height = "0px";
        shown.current = false;
        lastY.current = -1;
        return;
      }
      // Past the last row, "now" runs to where tomorrow starts, or the bottom.
      const at = (i: number) => (i < rows.length ? rows[i].offsetTop : after.current ? after.current.offsetTop : box.offsetHeight + GAP);
      const y = Math.max(0, at(from) + f * (at(to) - at(from)) - GAP / 2);
      // Across a row the line would strike through its text: there only the
      // dot shows, on the rail, and the line reaches out again in the open.
      mark.dataset.over = String([...rows].some((r) => y > r.offsetTop + 2 && y < r.offsetTop + r.offsetHeight - 2));
      // The observer calls this again right after each new minute's glide
      // starts; it has nothing to move then.
      if (Math.abs(y - lastY.current) < 0.5) return;
      lastY.current = y;
      const first = !shown.current;
      if (first) {
        mark.style.transition = "none";
        lived.style.transition = "none";
      }
      mark.style.translate = `0 ${y - DOT / 2}px`; // centred on y
      lived.style.height = `${Math.max(0, y - RAIL_TOP)}px`;
      if (first) {
        void mark.offsetHeight; // settle there before the transitions come back
        mark.style.transition = "";
        lived.style.transition = "";
        shown.current = true;
      }
      mark.style.opacity = "1";
    };
    place();
    const watch = new ResizeObserver(place);
    watch.observe(box);
    return () => watch.disconnect();
  }, [from, to, f, layout]);

  // On a wide screen the tile is as tall as the cards beside it and the list
  // scrolls inside it (out of flow, so it never sets that height itself).
  return (
    <div className="relative min-h-0 flex-1 xl:min-h-[440px]">
      <div
        ref={scroller}
        onWheel={() => (touched.current = true)}
        onTouchMove={() => (touched.current = true)}
        onPointerDown={(e) => e.target === e.currentTarget && (touched.current = true)} // its scrollbar
        onKeyDown={(e) => SCROLL_KEYS.has(e.key) && (touched.current = true)}
        className="-mt-1 overflow-y-auto pt-1 pr-2 [mask-image:linear-gradient(to_bottom,transparent,black_10px,black_calc(100%-24px),transparent)] lg:max-xl:max-h-[600px] xl:absolute xl:inset-0"
      >
        <div ref={track} className="relative pb-6">
          {/* The rail, and its part already lived. */}
          <span className="absolute top-3 bottom-3 w-px bg-border" style={{ left: RAIL_X - 0.5 }} aria-hidden="true" />
          <span ref={fill} className={cn("absolute top-3 w-[2px] rounded-full bg-primary/40", styles.fill)} style={{ left: RAIL_X - 1, height: 0 }} aria-hidden="true" />
          {items.length > 0 ? (
            <ol className="relative flex flex-col gap-2.5">
              {items.map((item, i) => (
                <DayRow key={item.key} item={item} state={rowState(item, i, items, now)} now={now} />
              ))}
            </ol>
          ) : null}
          {/* Tomorrow, under the last row: a preview, with nothing past, on now or next. */}
          {tomorrow.length > 0 ? (
            <>
              <div ref={after} className="mt-5 mb-2.5 grid grid-cols-[3.5rem_1.5rem_minmax(0,1fr)] gap-x-2">
                <div className="col-start-3 flex items-center gap-3 pr-2">
                  <span className="text-xs font-bold tracking-[0.12em] text-muted-foreground">TOMORROW</span>
                  <span className="h-px flex-1 bg-border" aria-hidden="true" />
                  <span className="text-xs text-muted-foreground" suppressHydrationWarning>
                    {tomorrowLabel(now, timeZone)} · {tomorrow.length === 1 ? "1 thing" : `${tomorrow.length} things`}
                  </span>
                </div>
              </div>
              <ol className="relative flex flex-col gap-2.5" aria-label="Tomorrow">
                {tomorrow.map((item) => (
                  <DayRow key={item.key} item={item} state="" now={now} preview />
                ))}
              </ol>
            </>
          ) : null}
          {/* Now: a calendar's red line (here in the brand blue), its arms
              folded away while it crosses a row. */}
          <div ref={line} className={cn("group pointer-events-none absolute inset-x-0 top-0 z-10 flex items-center opacity-0", styles.glide)} aria-hidden="true">
            <span className={cn("h-px bg-linear-to-r from-transparent to-primary/70", ARM)} style={{ width: RAIL_X - DOT / 2 }} />
            <span className="size-3 shrink-0 rounded-full bg-primary ring-4 ring-primary/20" />
            <span className={cn("h-px flex-1 bg-linear-to-r from-primary/70 via-primary/30 to-transparent", ARM)} />
          </div>
        </div>
      </div>
    </div>
  );
}

// `preview`: a row of tomorrow's, left out of the measurements that place the now line.
function DayRow({ item, state, now, preview = false }: { item: TimelineItem; state: ReturnType<typeof rowState>; now: number; preview?: boolean }) {
  const color = cssColor(item.color) ?? "#5B7CF5";
  const Icon = KIND_ICON[item.kind] ?? ZapIcon;
  const isEvent = item.kind === "event";
  const soon = state === "now" || state === "next";
  return (
    <li data-row={preview ? undefined : "true"} className={cn("grid grid-cols-[3.5rem_1.5rem_minmax(0,1fr)] gap-x-2 transition-opacity duration-700", state === "past" && "opacity-50")}>
      <div className="pt-3.5 text-right">
        <div className={cn("text-[15px] font-semibold tabular-nums", soon && "text-primary", item.allDay && "text-xs")}>{item.time}</div>
        {item.ampm ? <div className="text-[11px] text-muted-foreground">{item.ampm}</div> : null}
      </div>
      <div className="flex justify-center pt-[19px]" aria-hidden="true">
        <span
          className={cn("relative size-2.5 rounded-full ring-4 ring-card", state === "now" && "size-3")}
          style={{ background: state === "past" ? "var(--muted-foreground)" : color }}
        />
      </div>
      <Link
        href={item.href}
        className={cn(
          "flex min-w-0 items-start gap-3.5 rounded-[20px] px-4 py-3.5 text-foreground no-underline ring-1 transition-[background-color,box-shadow] outline-none focus-visible:ring-2 focus-visible:ring-ring",
          isEvent && state !== "now" ? "bg-card ring-border hover:bg-muted/50" : "bg-muted/70 ring-foreground/[0.04] hover:ring-foreground/15",
        )}
        style={state === "now" ? { boxShadow: `inset 0 0 0 2px ${color}`, backgroundColor: `color-mix(in oklab, ${color} 8%, var(--card))` } : undefined}
      >
        {item.imageUrl ? (
          // Pictures come from the agents' feeds, on any host; next/image would need each one allowed.
          // eslint-disable-next-line @next/next/no-img-element
          <img src={item.imageUrl} alt="" className="h-[72px] w-24 shrink-0 rounded-xl object-cover max-sm:hidden" style={{ background: color }} />
        ) : (
          <span className="relative grid size-9 shrink-0 place-items-center rounded-full" style={{ color }}>
            <span className="absolute inset-0 rounded-full opacity-15" style={{ background: color }} aria-hidden="true" />
            <Icon className="relative size-[18px]" />
          </span>
        )}
        <span className="min-w-0 flex-1">
          {!isEvent ? (
            <span className="block truncate text-[11px] font-bold tracking-[0.1em] uppercase" style={{ color }}>
              {item.label}
            </span>
          ) : null}
          <span className={cn("block text-[16px] leading-snug", item.kind === "news" || isEvent ? "font-semibold" : "font-medium", item.kind === "news" && "text-[17px]")}>
            {item.title}
          </span>
          {item.detail ? <span className="mt-0.5 line-clamp-2 block text-sm text-muted-foreground">{item.detail}</span> : null}
        </span>
        {soon ? (
          <span
            className={cn("shrink-0 self-center rounded-full px-3 py-1 text-xs font-semibold", state === "next" && "bg-primary/10 text-primary", state === "now" && "text-primary-foreground")}
            style={state === "now" ? { background: color } : undefined}
            suppressHydrationWarning
          >
            {state === "now" ? "Now" : untilLabel(item.startMs, now)}
          </span>
        ) : null}
      </Link>
    </li>
  );
}
