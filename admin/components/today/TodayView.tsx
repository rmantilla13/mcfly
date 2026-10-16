"use client";

import { cn } from "cn";
import {
  CalendarIcon,
  CircleAlertIcon,
  FileTextIcon,
  GitCommitHorizontalIcon,
  MonitorIcon,
  NewspaperIcon,
  ZapIcon,
} from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { AskPanel } from "./AskPanel";
import { FlipClock } from "./FlipClock";
import { cssColor } from "@/lib/format";
import type { TodayData } from "@/lib/today-data";
import { focusIndex, formatClock, greeting, rowState, untilLabel, upNext, type TimelineItem } from "@/lib/today";

// The web Today page: the display's Home, for a browser. The left column is
// the moment (greeting, clock, up next, anything blocked); the right is the
// day (markets, then one stream in time order, scrolled to "now").

export function useNow(initial: number, everyMs = 15_000): number {
  const [now, setNow] = useState(initial);
  useEffect(() => {
    const tick = () => setNow(Date.now());
    tick();
    const id = setInterval(tick, everyMs);
    return () => clearInterval(id);
  }, [everyMs]);
  return now;
}

// New pushes show up without a reload: the server components re-run.
export function useLiveRefresh(everyMs = 60_000) {
  const router = useRouter();
  useEffect(() => {
    const id = setInterval(() => router.refresh(), everyMs);
    return () => clearInterval(id);
  }, [router, everyMs]);
}

export function clockParts(ms: number, timeZone: string) {
  const [time, ampm] = formatClock(ms, timeZone).split(" ");
  const date = new Intl.DateTimeFormat("en-US", { timeZone, weekday: "long", month: "long", day: "numeric" }).format(new Date(ms));
  return { time, ampm: ampm.toUpperCase(), date };
}

const KIND_ICON = { news: NewspaperIcon, brief: FileTextIcon, alert: CircleAlertIcon, project: GitCommitHorizontalIcon, event: CalendarIcon };

export function TodayView({ data }: { data: TodayData }) {
  useLiveRefresh();
  const now = useNow(data.nowMs);
  const minute = Math.floor(now / 60_000) * 60_000;
  const tz = data.timeZone;
  const clock = clockParts(now, tz);
  const next = upNext(data.events, minute);
  const blocked = data.blocked[0];

  return (
    <div className="grid grid-cols-[minmax(0,5fr)_minmax(0,7fr)] gap-8 max-lg:grid-cols-1 max-lg:gap-6">
      {/* The moment. */}
      <section className="flex flex-col gap-4" aria-label="Now">
        <div>
          <p className="text-lg text-muted-foreground" suppressHydrationWarning>
            {greeting(now, tz, data.displayName)}
          </p>
          <p className="flex items-baseline gap-2" suppressHydrationWarning>
            <FlipClock time={clock.time} className="text-[96px] leading-none font-light tracking-[-0.04em] max-md:text-7xl" />
            <span className="text-xl text-muted-foreground">{clock.ampm}</span>
          </p>
          <p className="mt-1 text-[15px] text-muted-foreground" suppressHydrationWarning>
            {clock.date}
          </p>
        </div>

        {next ? (
          <Link
            href="/feed?tab=calendar"
            className="rounded-[28px] px-6 py-5 text-white no-underline shadow-lg transition-transform hover:-translate-y-0.5"
            style={{ background: next.color, boxShadow: `0 12px 30px -12px ${next.color}` }}
          >
            <span className="block text-xs font-bold tracking-[0.12em] uppercase opacity-90" suppressHydrationWarning>
              {Date.parse(next.starts_at) <= minute
                ? `Now · ends ${untilLabel(Date.parse(next.ends_at), minute)}`
                : `Up next · ${untilLabel(Date.parse(next.starts_at), minute)}`}
            </span>
            <span className="mt-1 block truncate text-2xl font-semibold">{next.title}</span>
            <span className="mt-0.5 block truncate text-[15px] opacity-90">
              {[`${formatClock(Date.parse(next.starts_at), tz)} – ${formatClock(Date.parse(next.ends_at), tz)}`, next.location || next.calendar].filter(Boolean).join(" · ")}
            </span>
          </Link>
        ) : null}

        {blocked ? (
          <Link
            href={`/feed/projects/${blocked.id}`}
            className="flex items-center gap-4 rounded-[28px] bg-destructive/10 px-5 py-4 text-foreground no-underline transition-colors hover:bg-destructive/15"
          >
            <span className="grid size-10 shrink-0 place-items-center rounded-full bg-destructive/15 text-destructive">
              <CircleAlertIcon className="size-5" />
            </span>
            <span className="min-w-0">
              <span className="block truncate text-[17px] font-semibold">
                {data.blocked.length > 1 ? `${blocked.name} and ${data.blocked.length - 1} more are blocked` : `${blocked.name} is blocked`}
              </span>
              {blocked.next ? <span className="block truncate text-sm text-muted-foreground">{blocked.next}</span> : null}
            </span>
          </Link>
        ) : null}

        <div className="mt-auto pt-2">
          <AskPanel />
        </div>
        <div className="flex flex-wrap gap-2.5">
          <Button asChild size="lg" className="rounded-full">
            <Link href="/ambient">
              <MonitorIcon data-icon="inline-start" />
              Ambient view
            </Link>
          </Button>
        </div>
      </section>

      {/* The day. */}
      <section className="flex min-w-0 flex-col gap-4" aria-label="Today">
        {data.tickers.length > 0 ? (
          <Link
            href="/feed?tab=markets"
            className="flex items-center gap-5 overflow-x-auto rounded-3xl [scrollbar-width:none] bg-card px-5 py-4 text-foreground no-underline ring-1 ring-foreground/5"
          >
            {data.tickers.map((t, i) => (
              <span key={t.symbol} className="flex shrink-0 items-center gap-2">
                {i > 0 ? <span className="mr-3 h-6 w-px bg-border" aria-hidden="true" /> : null}
                <strong className="font-semibold">{t.symbol}</strong>
                <span className="text-muted-foreground tabular-nums max-xl:hidden">{t.price}</span>
                <span
                  className={cn(
                    "font-semibold tabular-nums",
                    t.direction === "up" && "text-success",
                    t.direction === "down" && "text-destructive",
                  )}
                >
                  {t.change}
                </span>
              </span>
            ))}
          </Link>
        ) : null}

        <div className="flex items-center gap-3">
          <h2 className="text-xs font-bold tracking-[0.14em] text-muted-foreground uppercase">Today</h2>
          <span className="h-px flex-1 bg-border" aria-hidden="true" />
          <span className="text-xs text-muted-foreground">
            {data.timeline.length === 1 ? "1 thing" : `${data.timeline.length} things`}
          </span>
        </div>

        {data.timeline.length === 0 ? (
          <p className="text-muted-foreground">
            Nothing yet today. Briefs, the Pulse, project updates and your calendar land here as your agents push them.
          </p>
        ) : (
          <DayList items={data.timeline} now={minute} />
        )}
      </section>
    </div>
  );
}

function DayList({ items, now }: { items: TimelineItem[]; now: number }) {
  const listRef = useRef<HTMLOListElement>(null);
  const focus = Math.max(0, focusIndex(items, now) - 1);
  const touched = useRef(false);

  // Keep "now" in view, one row of context above, until someone scrolls.
  useEffect(() => {
    const list = listRef.current;
    if (!list || touched.current) return;
    const row = list.children[focus] as HTMLElement | undefined;
    if (row) list.scrollTo({ top: row.offsetTop - list.offsetTop, behavior: "smooth" });
  }, [focus]);

  return (
    <ol
      ref={listRef}
      onWheel={() => (touched.current = true)}
      onTouchMove={() => (touched.current = true)}
      className="flex max-h-[calc(100vh-260px)] min-h-[320px] flex-col gap-2.5 overflow-y-auto pr-1 max-lg:max-h-none"
    >
      {items.map((item, index) => (
        <DayRow key={item.key} item={item} state={rowState(item, index, items, now)} now={now} />
      ))}
    </ol>
  );
}

function DayRow({ item, state, now }: { item: TimelineItem; state: ReturnType<typeof rowState>; now: number }) {
  const color = cssColor(item.color) ?? "#5B7CF5";
  const Icon = KIND_ICON[item.kind] ?? ZapIcon;
  const isEvent = item.kind === "event";
  return (
    <li className={cn("flex gap-4 transition-opacity", state === "past" && "opacity-50")}>
      <div className="w-14 shrink-0 pt-4 text-right">
        <div className={cn("text-[15px] font-semibold tabular-nums", (state === "now" || state === "next") && "text-primary", item.allDay && "text-xs")}>
          {item.time}
        </div>
        {item.ampm ? <div className="text-[11px] text-muted-foreground">{item.ampm}</div> : null}
      </div>
      <Link
        href={item.href}
        className={cn(
          "flex min-w-0 flex-1 items-start gap-3.5 rounded-[22px] px-4 py-3.5 text-foreground no-underline transition-colors",
          isEvent && state !== "now" ? "ring-1 ring-border hover:bg-card/60" : "bg-card ring-1 ring-foreground/5 hover:bg-card/80",
        )}
        style={state === "now" ? { boxShadow: `inset 0 0 0 2px ${color}` } : undefined}
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
          <span className={cn("block text-[16px] leading-snug", item.kind === "news" || isEvent ? "font-semibold" : "font-medium", item.kind === "news" && "text-[18px]")}>
            {item.title}
          </span>
          {item.detail ? <span className="mt-0.5 line-clamp-2 block text-sm text-muted-foreground">{item.detail}</span> : null}
        </span>
        {state === "now" || state === "next" ? (
          <span
            className={cn("shrink-0 self-center rounded-full px-3 py-1 text-xs font-semibold", state === "next" && "bg-primary/10 text-primary")}
            style={state === "now" ? { background: color, color: "white" } : undefined}
            suppressHydrationWarning
          >
            {state === "now" ? "Now" : untilLabel(item.startMs, now)}
          </span>
        ) : null}
      </Link>
    </li>
  );
}
