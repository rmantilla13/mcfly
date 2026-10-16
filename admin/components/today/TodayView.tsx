"use client";

import { cn } from "cn";
import { MonitorIcon } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import BlurText from "@/components/reactbits/BlurText";
import { dateFormat, dayKey } from "@/lib/events";
import { buildSuggestions, SUMMARIZE_DAY } from "@/lib/suggestions";
import type { TodayData } from "@/lib/today-data";
import { formatClock, greeting, upNext } from "@/lib/today";
import { AskTile } from "./AskTile";
import { BriefCard } from "./BriefCard";
import { DayTimeline } from "./DayTimeline";
import { FlipClock } from "./FlipClock";
import { InsightsStrip } from "./InsightsStrip";
import { MarketTiles } from "./MarketTiles";
import { MetricTiles } from "./MetricTiles";
import { NeedsYouCard } from "./NeedsYouCard";
import { PulseCard } from "./PulseCard";
import { Tile } from "./Tile";
import { UpNextCard } from "./UpNextCard";

// The web Today page: the display's Home, for a browser, as a bento of
// tiles. Across the top, the moment (greeting and clock), what's on now or
// next, and anything blocked; then what McFly noticed beside asking it;
// the markets and the agents' numbers; and the day itself, on a rail, with
// the newest brief and today's Pulse beside it. Twelve columns on a wide
// screen, six on a laptop, one on a phone (app/(console)/today/loading.tsx
// draws the same grid while it loads).

// The time, ticking on the wall clock's own boundaries (every whole
// `everyMs`, just after it), so a clock showing minutes turns with the minute
// rather than up to a tick late. A tab coming back catches up at once.
export function useNow(initial: number, everyMs = 15_000): number {
  const [now, setNow] = useState(initial);
  useEffect(() => {
    let id: ReturnType<typeof setTimeout> | undefined;
    const tick = () => {
      clearTimeout(id);
      setNow(Date.now());
      id = setTimeout(tick, everyMs - (Date.now() % everyMs) + 20);
    };
    const onVisible = () => {
      if (!document.hidden) tick();
    };
    tick();
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      clearTimeout(id);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [everyMs]);
  return now;
}

// New pushes show up without a reload: the server components re-run every
// `everyMs`. Not while the tab is hidden, though: a tab left open in the
// background all day would read every feed 1,440 times for nobody. When it
// comes back it refreshes at once if one came due meanwhile, then carries on.
export function useLiveRefresh(everyMs = 60_000) {
  const router = useRouter();
  useEffect(() => {
    let last = Date.now();
    let id: ReturnType<typeof setTimeout> | undefined;
    const tick = () => {
      id = undefined;
      if (document.hidden) return; // picked up again by onVisible
      last = Date.now();
      router.refresh();
      id = setTimeout(tick, everyMs);
    };
    const onVisible = () => {
      if (document.hidden) return;
      clearTimeout(id);
      id = setTimeout(tick, Math.max(0, last + everyMs - Date.now()));
    };
    id = setTimeout(tick, everyMs);
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      clearTimeout(id);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [router, everyMs]);
}

export function clockParts(ms: number, timeZone: string) {
  const [time, ampm] = formatClock(ms, timeZone).split(" ");
  const date = dateFormat("en-US", { timeZone, weekday: "long", month: "long", day: "numeric" }).format(new Date(ms));
  return { time, ampm: ampm.toUpperCase(), date };
}

export function TodayView({ data }: { data: TodayData }) {
  useLiveRefresh();
  // Whole minutes: the clock flips on the minute, and so does everything
  // that counts down to something.
  const now = useNow(data.nowMs, 60_000);
  const minute = Math.floor(now / 60_000) * 60_000;
  const tz = data.timeZone;
  const day = dayKey(new Date(minute), tz);
  const next = upNext(data.events, minute);
  const blocked = data.blocked.length > 0;
  const side = [data.brief, data.hero].filter(Boolean).length;
  // The chips: the server's suggestions, worked out again from the same rows
  // and clock but without the one the digest's button asks, so four others fit.
  const chips = buildSuggestions(data, data.nowMs, [SUMMARIZE_DAY]);
  let i = 0; // the order tiles rise in

  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-6 xl:grid-cols-12">
      {/* The moment, what's next, what needs you. */}
      <Moment
        now={minute}
        data={data}
        index={i++}
        className={cn(
          "lg:col-span-3",
          next && blocked && "xl:col-span-4",
          next && !blocked && "xl:col-span-5",
          !next && blocked && "xl:col-span-7",
          !next && !blocked && "lg:col-span-6 xl:col-span-12",
        )}
      />
      {next ? <UpNextCard event={next} now={minute} timeZone={tz} index={i++} className={cn("lg:col-span-3", blocked ? "xl:col-span-5" : "xl:col-span-7")} /> : null}
      {blocked ? (
        <NeedsYouCard blocked={data.blocked} index={i++} className={cn(next ? "lg:col-span-6 xl:col-span-3" : "lg:col-span-3 xl:col-span-5")} />
      ) : null}

      {/* What McFly noticed, and asking it. */}
      <InsightsStrip insights={data.insights} index={i++} className="lg:col-span-6 xl:col-span-7" />
      <AskTile day={day} timeZone={tz} suggestions={chips} index={i++} className="lg:col-span-6 xl:col-span-5" />

      {/* The numbers. */}
      {data.tickers.length ? (
        <MarketTiles tickers={data.tickers} index={i++} className={cn("lg:col-span-6", data.metrics.length ? "xl:col-span-8" : "xl:col-span-12")} />
      ) : null}
      {data.metrics.length ? (
        <MetricTiles metrics={data.metrics} alone={!data.tickers.length} index={i++} className={cn("lg:col-span-6", data.tickers.length ? "xl:col-span-4" : "xl:col-span-12")} />
      ) : null}

      {/* The day, with the newest brief and today's Pulse beside it. */}
      <DayTimeline
        items={data.timeline}
        tomorrow={data.tomorrow}
        now={minute}
        timeZone={tz}
        index={i++}
        className={cn("lg:col-span-6", side ? "xl:col-span-7" : "xl:col-span-12", side === 2 && "xl:row-span-2")}
      />
      {data.brief ? <BriefCard brief={data.brief} now={minute} timeZone={tz} index={i++} className={cn("xl:col-span-5", data.hero ? "lg:col-span-3" : "lg:col-span-6")} /> : null}
      {data.hero ? <PulseCard hero={data.hero} index={i++} className={cn("xl:col-span-5", data.brief ? "lg:col-span-3" : "lg:col-span-6")} /> : null}
    </div>
  );
}

// Greeting (arriving a word at a time, out of a blur: React Bits' BlurText),
// the clock (its digits flip as the minute turns) and the date, and the way
// to the ambient view.
function Moment({ now, data, index, className }: { now: number; data: TodayData; index: number; className?: string }) {
  const clock = clockParts(now, data.timeZone);
  return (
    <Tile index={index} label="Now" className={cn("justify-between gap-4 p-6 max-sm:p-5", className)}>
      <div className="flex items-start gap-3">
        <BlurText
          text={greeting(now, data.timeZone, data.displayName)}
          className="min-w-0 flex-1 text-lg text-muted-foreground"
          trigger="load"
          delay={70}
          stepDuration={0.3}
          blur={8}
          distance={14}
        />
        <Link
          href="/ambient"
          className="-mt-1 -mr-1 flex h-9 shrink-0 items-center gap-2 rounded-full px-3 text-[13px] font-medium text-muted-foreground no-underline transition-colors hover:bg-muted hover:text-foreground"
        >
          <MonitorIcon className="size-4" aria-hidden="true" />
          <span className="max-sm:sr-only">Ambient</span>
        </Link>
      </div>
      <div>
        <p className="flex items-baseline gap-2" suppressHydrationWarning>
          <FlipClock time={clock.time} className="text-[88px] leading-none font-light tracking-[-0.04em] max-md:text-7xl" />
          <span className="text-xl text-muted-foreground">{clock.ampm}</span>
        </p>
        <p className="mt-2 text-[15px] text-muted-foreground" suppressHydrationWarning>
          {clock.date}
        </p>
      </div>
    </Tile>
  );
}
