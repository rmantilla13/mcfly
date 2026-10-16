"use client";

import { cn } from "cn";
import { ChartSplineIcon, MicIcon, MonitorIcon } from "lucide-react";
import Link from "next/link";
import { useRef } from "react";
import { SpectrumGlow, type GlowInput } from "@/components/voice/SpectrumGlow";
import { glance } from "@/lib/glance";
import type { TodayData } from "@/lib/today-data";
import { BriefCard } from "./BriefCard";
import { NeedsYouCard } from "./NeedsYouCard";
import { PulseCard } from "./PulseCard";
import { Tile, TileHead } from "./Tile";
import { clockParts, useLiveRefresh, useNow } from "./TodayView";
import { UpNextCard } from "./UpNextCard";

// Today with the assistant first (the switcher's Assistant; the display's
// own, HomeAssistant.qml): McFly speaks before you ask. A dark card on the
// voice glow says what matters now (lib/glance.ts, worded as the display
// words it), offers the follow-ups (each opens the full-screen Ask with it
// asked) and the way to talk (/voice). Beside it, the cards the summary came
// from: what's next, the markets, what's blocked, today's Pulse (or the
// newest brief). Who answers is the platform's setting, so it's said, with
// the way to change it, rather than offered as a switch here.

export function TodayAssistant({ data, provider }: { data: TodayData; provider: "claude" | "grok" }) {
  useLiveRefresh();
  const now = useNow(data.nowMs, 60_000);
  const minute = Math.floor(now / 60_000) * 60_000;
  const tz = data.timeZone;
  const clock = clockParts(minute, tz);
  const g = glance(data, minute);
  // Nothing heard or said: the glow's quiet idle (20 frames a second).
  const glow = useRef<GlowInput>({ level: 0, low: 0, mid: 0, high: 0, processing: false, speaking: false });
  const markets = g.movers.length ? g.movers : data.tickers.slice(0, 3);
  const brief = data.brief?.title ? data.brief : null;
  const evidence = !!g.next || markets.length > 0 || data.blocked.length > 0 || !!data.hero || !!brief;
  let i = 1; // the order cards rise in, after the main one

  return (
    <div className="grid grid-cols-1 gap-4 xl:grid-cols-12">
      <section
        aria-label="McFly"
        className={cn(
          "relative flex min-h-[560px] flex-col gap-5 overflow-hidden rounded-[36px] bg-[#1B1A1F] p-10 text-white max-sm:min-h-[480px] max-sm:p-6",
          evidence ? "xl:col-span-8" : "xl:col-span-12",
        )}
      >
        <SpectrumGlow input={glow} radius={36} className="pointer-events-none absolute inset-x-0 bottom-0 h-[58%] w-full" />

        <div className="relative flex flex-wrap items-center gap-3">
          <p className="text-[15px] text-white/65" suppressHydrationWarning>
            {clock.time} {clock.ampm} · {clock.date.split(",")[0]}
          </p>
          <Link
            href="/settings"
            className="ml-auto flex h-9 items-center rounded-full bg-white/10 px-3.5 text-[13px] font-semibold text-white no-underline transition-colors hover:bg-white/15"
          >
            {provider === "grok" ? "Grok" : "Claude"} answers
          </Link>
          <Link
            href="/ambient"
            className="flex h-9 items-center gap-2 rounded-full px-3 text-[13px] font-medium text-white/70 no-underline transition-colors hover:bg-white/10 hover:text-white max-sm:hidden"
          >
            <MonitorIcon className="size-4" aria-hidden="true" />
            Ambient
          </Link>
        </div>

        <h1 className="relative text-[40px] leading-[1.16] font-medium tracking-[-0.01em] text-balance max-md:text-[30px] max-sm:text-[26px]" suppressHydrationWarning>
          {g.headline}
        </h1>
        <p className="relative max-w-[60ch] text-[19px] leading-[1.45] text-white/80 max-sm:text-base" suppressHydrationWarning>
          {g.detail}
        </p>

        <ul className="relative flex flex-wrap gap-2.5" aria-label="Ask about it">
          {g.chips.map((q) => (
            <li key={q} className="min-w-0">
              <Link
                href={`/ask?q=${encodeURIComponent(q)}`}
                className="flex h-12 max-w-full items-center rounded-full bg-white/[0.08] px-5 text-[15px] text-white no-underline ring-1 ring-white/20 transition-colors outline-none hover:bg-white/15 focus-visible:ring-2 focus-visible:ring-white"
              >
                <span className="truncate">{q}</span>
              </Link>
            </li>
          ))}
        </ul>

        <div className="flex-1" />

        <div className="relative flex items-center gap-4">
          <Link
            href="/voice"
            aria-label="Talk to McFly"
            className="flex size-[84px] shrink-0 items-center justify-center rounded-full bg-white text-[#1B1A1F] no-underline shadow-lg transition-transform outline-none hover:scale-[1.03] focus-visible:ring-4 focus-visible:ring-white/50 max-sm:size-16"
          >
            <MicIcon className="size-8 max-sm:size-6" aria-hidden="true" />
          </Link>
          <p className="text-[17px] text-white/85 max-sm:text-[15px]">Talk to McFly, or tap a question above</p>
        </div>
      </section>

      {evidence ? (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:col-span-4 xl:flex xl:flex-col">
          {g.next ? <UpNextCard event={g.next} now={minute} timeZone={tz} index={i++} /> : null}
          {markets.length ? <Movers tickers={markets} moving={g.movers.length > 0} index={i++} /> : null}
          {data.blocked.length ? <NeedsYouCard blocked={data.blocked} index={i++} /> : null}
          {data.hero ? (
            <PulseCard hero={data.hero} index={i++} className="xl:flex-1" />
          ) : brief ? (
            <BriefCard brief={brief} now={minute} timeZone={tz} index={i++} className="xl:flex-1" />
          ) : null}
        </div>
      ) : null}
    </div>
  );
}

// The markets behind the headline: the movers, biggest first (or the first
// few, on a quiet day).
function Movers({ tickers, moving, index }: { tickers: TodayData["tickers"]; moving: boolean; index: number }) {
  return (
    <Tile href="/feed?tab=markets" index={index} className="gap-3 p-5">
      <TileHead icon={<ChartSplineIcon />}>{moving ? "Moving" : "Markets"}</TileHead>
      <ul className="flex flex-col gap-2">
        {tickers.map((t) => (
          <li key={t.symbol} className="flex items-baseline gap-3 text-[16px]">
            <strong className="w-16 shrink-0 truncate font-semibold">{t.symbol}</strong>
            <span className="flex-1 text-right tabular-nums">{t.price}</span>
            <span
              className={cn(
                "w-[4.5rem] text-right font-semibold tabular-nums",
                t.direction === "up" && "text-success",
                t.direction === "down" && "text-destructive",
                t.direction === "flat" && "text-muted-foreground",
              )}
            >
              {t.change}
            </span>
          </li>
        ))}
      </ul>
    </Tile>
  );
}
