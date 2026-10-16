"use client";

import { cn } from "cn";
import {
  ArrowRightIcon,
  CalendarDaysIcon,
  ChartSplineIcon,
  GaugeIcon,
  MonitorIcon,
  SparklesIcon,
} from "lucide-react";
import Link from "next/link";
import { Sparkline } from "@/components/charts/Sparkline";
import { dayKey, dayLabel } from "@/lib/events";
import { cssColor } from "@/lib/format";
import type { Insight, TodayData } from "@/lib/today-data";
import { formatClock, greeting, upNext } from "@/lib/today";
import { NeedsYouCard } from "./NeedsYouCard";
import { PulseCard } from "./PulseCard";
import { Tile, TileHead } from "./Tile";
import { clockParts, useLiveRefresh, useNow } from "./TodayView";
import { UpNextCard } from "./UpNextCard";

// Today as a bento (the switcher's Bento; the display's own, HomeBento.qml):
// the time and what McFly noticed in one line, then tiles, each a door into
// its page. The newest brief is the big tile, on a gradient of its agent's
// colour; beside it what's next and a number; the markets on the right; then
// what's blocked, what's coming and today's Pulse. A tile with nothing to
// show isn't drawn and the grid closes up; a new account sees where its
// briefs will land and what to connect. Twelve columns wide, six on a
// laptop, one on a phone.

// A noticed thing as a pill; a door when it has somewhere to go.
const PILL =
  "flex h-9 max-w-[18rem] items-center gap-2 rounded-full bg-card px-3.5 text-[13px] font-semibold text-foreground ring-1 ring-foreground/[0.06]";

const TONE: Record<Insight["tone"], string> = {
  good: "bg-success",
  bad: "bg-destructive",
  warn: "bg-amber-500",
  neutral: "bg-muted-foreground/60",
};

export function TodayBento({ data }: { data: TodayData }) {
  useLiveRefresh();
  const now = useNow(data.nowMs, 60_000);
  const minute = Math.floor(now / 60_000) * 60_000;
  const tz = data.timeZone;
  const clock = clockParts(minute, tz);
  const next = upNext(data.events, minute);
  const later = data.events
    .filter((e) => e !== next && !e.all_day && Date.parse(e.ends_at) > minute)
    .sort((a, b) => Date.parse(a.starts_at) - Date.parse(b.starts_at))
    .slice(0, 3);
  const brief = data.brief?.title ? data.brief : null;
  const empty =
    !brief &&
    !next &&
    !later.length &&
    !data.tickers.length &&
    !data.metrics.length &&
    !data.hero &&
    !data.blocked.length;
  let i = 0; // the order tiles rise in

  return (
    <div className="flex flex-col gap-4">
      {/* The time, the day, what McFly noticed. */}
      <div className="flex flex-wrap items-center gap-x-5 gap-y-3">
        <p className="flex items-baseline gap-1.5" suppressHydrationWarning>
          <span className="text-5xl leading-none font-light tracking-[-0.03em]">
            {clock.time}
          </span>
          <span className="text-base text-muted-foreground">{clock.ampm}</span>
        </p>
        <div className="min-w-0">
          <p className="text-base font-semibold" suppressHydrationWarning>
            {clock.date}
          </p>
          <p
            className="text-[13px] text-muted-foreground"
            suppressHydrationWarning
          >
            {greeting(minute, tz, data.displayName)}
          </p>
        </div>
        <Link
          href="/ambient"
          className="flex h-9 items-center gap-2 rounded-full px-3 text-[13px] font-medium text-muted-foreground no-underline transition-colors hover:bg-muted hover:text-foreground max-sm:hidden"
        >
          <MonitorIcon className="size-4" aria-hidden="true" />
          Ambient
        </Link>
        {data.insights.length ? (
          <ul
            className="flex flex-wrap gap-2 lg:ml-auto"
            aria-label="What McFly noticed"
          >
            {data.insights.slice(0, 4).map((n, k) => (
              <li
                key={n.title}
                className={cn("min-w-0", k >= 2 && "max-sm:hidden")}
              >
                {n.href ? (
                  <Link
                    href={n.href}
                    className={cn(
                      PILL,
                      "no-underline transition-colors outline-none hover:ring-foreground/15 focus-visible:ring-2 focus-visible:ring-ring",
                    )}
                  >
                    <span
                      className={cn(
                        "size-2 shrink-0 rounded-full",
                        TONE[n.tone],
                      )}
                      aria-hidden="true"
                    />
                    <span className="truncate">{n.title}</span>
                  </Link>
                ) : (
                  <span className={PILL}>
                    <span
                      className={cn(
                        "size-2 shrink-0 rounded-full",
                        TONE[n.tone],
                      )}
                      aria-hidden="true"
                    />
                    <span className="truncate">{n.title}</span>
                  </span>
                )}
              </li>
            ))}
          </ul>
        ) : null}
      </div>

      <div className="grid grid-flow-row-dense grid-cols-1 gap-4 lg:grid-cols-6 xl:auto-rows-[minmax(176px,auto)] xl:grid-cols-12">
        <HeroBrief
          data={data}
          now={minute}
          index={i++}
          className="lg:col-span-6 xl:col-span-5 xl:row-span-2"
        />
        {next ? (
          <UpNextCard
            event={next}
            now={minute}
            timeZone={tz}
            index={i++}
            className="lg:col-span-3 xl:col-span-3"
          />
        ) : null}
        {data.tickers.length ? (
          <Markets
            data={data}
            index={i++}
            className="lg:col-span-3 lg:row-span-2 xl:col-span-4 xl:row-span-2"
          />
        ) : null}
        {data.metrics.length ? (
          <Numbers
            data={data}
            index={i++}
            className="lg:col-span-3 xl:col-span-3"
          />
        ) : null}
        {data.blocked.length ? (
          <NeedsYouCard
            blocked={data.blocked}
            index={i++}
            className="lg:col-span-6 xl:col-span-5"
          />
        ) : null}
        {later.length ? (
          <ComingUp
            events={later}
            now={minute}
            timeZone={tz}
            index={i++}
            className="lg:col-span-3 xl:col-span-3"
          />
        ) : null}
        {data.hero ? (
          <PulseCard
            hero={data.hero}
            index={i++}
            className="lg:col-span-3 xl:col-span-4"
          />
        ) : null}

        {/* Nothing at all yet: what to connect. */}
        {empty ? (
          <>
            <Start
              href="/calendars"
              index={i++}
              icon={<CalendarDaysIcon />}
              title="Nothing on the calendar"
              hint="Add a calendar's iCal link and what's next shows here."
              action="Add a calendar"
              className="lg:col-span-3 xl:col-span-7"
            />
            <Start
              href="/bots"
              index={i++}
              icon={<SparklesIcon />}
              title="Nothing from your agents yet"
              hint="Briefs, markets and news from agents and Grok bots fill these tiles."
              action="Make a Grok bot"
              className="lg:col-span-3 xl:col-span-7"
            />
          </>
        ) : null}
      </div>
    </div>
  );
}

// The newest brief on a gradient of its agent's colour; with none yet, where
// they'll land. Mixed with the card's own colour, so it darkens with the theme.
function HeroBrief({
  data,
  now,
  index,
  className,
}: {
  data: TodayData;
  now: number;
  index: number;
  className?: string;
}) {
  const brief = data.brief?.title ? data.brief : null;
  const c = cssColor(brief?.color) ?? "var(--glow-1)";
  const background = [
    `radial-gradient(120% 90% at 85% 8%, color-mix(in oklab, var(--glow-2) 30%, transparent) 0%, transparent 55%)`,
    `radial-gradient(90% 90% at 8% 100%, color-mix(in oklab, var(--glow-1) 34%, transparent) 0%, transparent 60%)`,
    `color-mix(in oklab, ${c} 34%, var(--card))`,
  ].join(", ");
  const tz = data.timeZone;
  const when = brief
    ? (() => {
        const at = Date.parse(brief.publishedAt);
        const day = dayLabel(dayKey(new Date(at), tz), tz, new Date(now));
        return day === "Today" ? formatClock(at, tz) : day;
      })()
    : "";
  return (
    <Tile
      href={brief ? "/feed?tab=briefs" : "/bots"}
      index={index}
      className={cn(
        "min-h-[340px] gap-3 overflow-hidden p-7 max-sm:p-5",
        className,
      )}
      style={{ background }}
    >
      <p
        className="text-xs font-bold tracking-[0.12em] text-foreground/70 uppercase"
        suppressHydrationWarning
      >
        {brief ? [brief.agent, when].filter(Boolean).join(" · ") : "Briefs"}
      </p>
      <h2 className="text-[34px] leading-[1.08] font-semibold tracking-[-0.01em] text-balance max-md:text-[28px]">
        {brief ? brief.title : "Your briefs land here"}
      </h2>
      <p className="line-clamp-6 text-[17px] leading-relaxed text-foreground/80">
        {brief
          ? brief.summary
          : "A Grok bot's report, an agent's check-in: the newest one fills this tile."}
      </p>
      {brief && brief.bullets.length ? (
        <ul className="flex flex-col gap-1 text-[15px] text-foreground/80">
          {brief.bullets.slice(0, 3).map((b) => (
            <li key={b} className="flex gap-2">
              <span aria-hidden="true">•</span>
              <span className="line-clamp-1">{b}</span>
            </li>
          ))}
        </ul>
      ) : null}
      <p className="mt-auto flex items-center gap-1.5 pt-2 text-[15px] font-semibold">
        {brief ? "All briefs" : "Make a Grok bot"}
        <ArrowRightIcon className="size-4" aria-hidden="true" />
      </p>
    </Tile>
  );
}

// The markets as lines: symbol, the last thirty points, the price, the move.
function Markets({
  data,
  index,
  className,
}: {
  data: TodayData;
  index: number;
  className?: string;
}) {
  return (
    <Tile
      href="/feed?tab=markets"
      index={index}
      className={cn("gap-3 p-5", className)}
    >
      <TileHead icon={<ChartSplineIcon />}>Markets</TileHead>
      <ul className="flex flex-col gap-2.5">
        {data.tickers.map((t) => (
          <li
            key={t.symbol}
            className="grid grid-cols-[3.5rem_minmax(0,1fr)_auto_4.5rem] items-center gap-3"
          >
            <strong className="truncate text-[15px] font-semibold">
              {t.symbol}
            </strong>
            <Sparkline
              points={t.points}
              tone={
                t.direction === "up"
                  ? "up"
                  : t.direction === "down"
                    ? "down"
                    : "neutral"
              }
              dot={false}
              className="h-7 w-full"
            />
            <span className="text-[15px] tabular-nums">{t.price}</span>
            <span
              className={cn(
                "text-right text-[15px] font-semibold tabular-nums",
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

// The first number on the boards, big, and the next two under it.
function Numbers({
  data,
  index,
  className,
}: {
  data: TodayData;
  index: number;
  className?: string;
}) {
  const [first, ...rest] = data.metrics;
  return (
    <Tile
      href="/feed?tab=metrics"
      index={index}
      className={cn("gap-1 p-5", className)}
    >
      <TileHead icon={<GaugeIcon />}>{first.label}</TileHead>
      <p className="text-4xl font-semibold tracking-[-0.02em] tabular-nums">
        {first.valueLabel}
      </p>
      {first.deltaLabel ? (
        <p
          className={cn(
            "text-[15px] font-semibold",
            first.good === true && "text-success",
            first.good === false && "text-destructive",
            first.good == null && "text-muted-foreground",
          )}
        >
          {first.deltaLabel}
        </p>
      ) : null}
      {rest.length ? (
        <ul className="mt-auto flex flex-col gap-1 pt-3">
          {rest.slice(0, 2).map((m) => (
            <li key={m.key} className="flex items-baseline gap-3 text-[14px]">
              <span className="min-w-0 flex-1 truncate text-muted-foreground">
                {m.label}
              </span>
              <span className="font-semibold tabular-nums">{m.valueLabel}</span>
            </li>
          ))}
        </ul>
      ) : null}
    </Tile>
  );
}

// What's coming after the next one.
function ComingUp({
  events,
  now,
  timeZone,
  index,
  className,
}: {
  events: TodayData["events"];
  now: number;
  timeZone: string;
  index: number;
  className?: string;
}) {
  return (
    <Tile
      href="/feed?tab=calendar"
      index={index}
      className={cn("gap-3 p-5", className)}
    >
      <TileHead icon={<CalendarDaysIcon />}>Coming up</TileHead>
      <ul className="flex flex-col gap-2.5">
        {events.map((e) => {
          const at = Date.parse(e.starts_at);
          const day = dayLabel(
            dayKey(new Date(at), timeZone),
            timeZone,
            new Date(now),
          );
          return (
            <li key={e.id} className="flex items-center gap-3">
              <span
                className="h-6 w-1 shrink-0 rounded-full"
                style={{ background: cssColor(e.color) ?? "var(--primary)" }}
                aria-hidden="true"
              />
              <span
                className="shrink-0 text-[13px] text-muted-foreground tabular-nums"
                suppressHydrationWarning
              >
                {day === "Today" ? formatClock(at, timeZone) : day}
              </span>
              <span className="min-w-0 truncate text-[15px] font-semibold">
                {e.title}
              </span>
            </li>
          );
        })}
      </ul>
    </Tile>
  );
}

// What to connect, while there's nothing to show.
function Start({
  href,
  index,
  icon,
  title,
  hint,
  action,
  className,
}: {
  href: string;
  index: number;
  icon: React.ReactNode;
  title: string;
  hint: string;
  action: string;
  className?: string;
}) {
  return (
    <Tile
      href={href}
      index={index}
      className={cn("justify-center gap-2 p-7", className)}
    >
      <span
        className="mb-1 flex size-11 items-center justify-center rounded-full bg-primary/10 text-primary [&_svg]:size-5"
        aria-hidden="true"
      >
        {icon}
      </span>
      <h2 className="text-xl font-semibold">{title}</h2>
      <p className="text-[15px] text-muted-foreground">{hint}</p>
      <p className="mt-2 flex items-center gap-1.5 text-[15px] font-semibold text-primary">
        {action}
        <ArrowRightIcon className="size-4" aria-hidden="true" />
      </p>
    </Tile>
  );
}
