"use client";

import { cn } from "cn";
import { SparklesIcon } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useState, useSyncExternalStore, type CSSProperties } from "react";
import type { TodayData } from "@/lib/today-data";
import { isNight } from "@/lib/mood";
import { formatClock, railWindow, stampLabel, untilLabel } from "@/lib/today";
import { GlowAurora } from "@/components/GlowAurora";
import { MeshGradient } from "@/components/MeshGradient";
import { SkyBackdrop } from "@/components/SkyBackdrop";
import DecryptedText from "@/components/reactbits/DecryptedText";
import { clockParts, useLiveRefresh, useNow } from "./TodayView";

// The display's ambient screen saver, in a browser: readable from across
// the room on a spare monitor or a tablet. The display's backdrop fills the
// screen: its moving gradient (MeshGradient, with its two glass rings) or,
// where the display's settings chose one (data.backdrop), one of its skies
// (SkyBackdrop). The clock and what's next sit on it, and a rail of cards
// from the feeds rises in along the bottom. Any click or key goes back to Today. The whole composition
// moves a few pixels every minute against burn-in.
//
// Under the date, what McFly noticed (lib/insights.ts) turns over one line
// at a time, cross-fading every 12 s. When there are more cards than the
// rail has room for (four, three or two by the screen's width), the rail
// turns through them, one card every 20 s, fading out and back in as it
// does; a blocked project stays put. Both follow the clock, so nothing else
// keeps time.
//
// Night is the display's (21:30 to 6:30, in its zone) and arrives as a slow
// cross-fade: the gradient deepens over 90 s, the cards and text change
// halfway, and an aurora in the night glow fades in over the clock
// (GlowAurora; the display's saver has the same one). A sky deepens over the
// same 90 s and is its own picture at night, with no aurora. Colours are the
// .ambient tokens in globals.css. This page stays up all night, so the
// backdrop and the aurora draw 15 frames a second at half the device's pixel
// ratio: one canvas pixel per CSS pixel on a 2x tablet, half that on a 1x
// monitor.

type Card = "brief" | "markets" | "metrics" | "blocked" | "pulse" | "later";

const MINUTE = 60_000;
const NOTICED_MS = 12_000; // each noticed line's turn
const RAIL_TURN_MS = 20_000; // the rail moves on by one card

// How many cards fit across: the rail's columns at xl, lg and below (the
// grid's own breakpoints).
const WIDE = "(min-width: 80rem)";
const MID = "(min-width: 64rem)";
function watchSlots(onChange: () => void) {
  const lists = [WIDE, MID].map((q) => window.matchMedia(q));
  lists.forEach((l) => l.addEventListener("change", onChange));
  return () => lists.forEach((l) => l.removeEventListener("change", onChange));
}
const slotsNow = () => (window.matchMedia(WIDE).matches ? 4 : window.matchMedia(MID).matches ? 3 : 2);

export function AmbientView({ data }: { data: TodayData }) {
  useLiveRefresh();
  const router = useRouter();
  const now = useNow(data.nowMs, 1_000);
  const minute = Math.floor(now / MINUTE) * MINUTE;
  const tz = data.timeZone;
  const clock = clockParts(now, tz);
  const night = isNight(now, tz);
  // The display's backdrop (Displays → Customize): a sky, or the mesh.
  const sky = data.backdrop === "mesh" ? null : data.backdrop;
  // The mesh's aurora is up from 20:45 to 6:45, so it's already there (and
  // still) when night starts, and fades out well before it goes. Once faded
  // out it stops drawing; a mount outside the night starts out faded.
  const auroraUp = !sky && (isNight(now + 45 * MINUTE, tz) || isNight(now - 15 * MINUTE, tz));
  const [auroraFaded, setAuroraFaded] = useState(!night);

  // Burn-in: a new small offset every minute.
  const [shift, setShift] = useState({ x: 0, y: 0 });
  useEffect(() => {
    const id = setInterval(() => setShift({ x: (Math.random() - 0.5) * 32, y: (Math.random() - 0.5) * 20 }), 60_000);
    return () => clearInterval(id);
  }, []);

  // Any key or click wakes back to Today.
  useEffect(() => {
    const wake = () => router.push("/today");
    window.addEventListener("keydown", wake);
    return () => window.removeEventListener("keydown", wake);
  }, [router]);

  const today = new Intl.DateTimeFormat("en-CA", { timeZone: tz }).format(new Date(now));
  const dayOf = (iso: string) => new Intl.DateTimeFormat("en-CA", { timeZone: tz }).format(new Date(iso));
  const todays = data.events.filter((e) => !e.all_day && Date.parse(e.ends_at) > minute && dayOf(e.starts_at) === today);
  const next = todays[0];
  const later = todays.slice(1, 3);
  const at = (iso: string) => formatClock(Date.parse(iso), tz);

  const nextLine = !next
    ? ""
    : Date.parse(next.starts_at) <= minute
      ? `${next.title}, until ${at(next.ends_at)}`
      : Date.parse(next.starts_at) - minute < 3_600_000
        ? `${next.title} ${untilLabel(Date.parse(next.starts_at), minute, true)}`
        : `${next.title} at ${at(next.starts_at)}`;
  const thenLine = later.length ? `Then ${later.map((e) => `${e.title} at ${at(e.starts_at)}`).join(" · ")}` : "";

  const cards: Card[] = [];
  if (data.brief) cards.push("brief");
  if (data.tickers.length) cards.push("markets");
  if (data.blocked.length) cards.push("blocked");
  if (data.hero) cards.push("pulse");
  if (data.metrics.length) cards.push("metrics");
  if (todays.length > 3) cards.push("later");
  // Four on the server, where there is no screen; the CSS below hides the
  // extra ones until the browser says how many fit.
  const slots = useSyncExternalStore(watchSlots, slotsNow, () => 4);
  // What needs you stays put; the rest take turns beside it.
  const pinned = cards.filter((c) => c === "blocked");
  const rail = railWindow(
    cards.filter((c) => c !== "blocked"),
    slots - pinned.length,
    now,
    RAIL_TURN_MS,
  );
  const noticed = data.insights;
  const noticing = noticed.length ? Math.floor(now / NOTICED_MS) % noticed.length : -1;

  const kicker = "ambient-tint text-xs font-bold tracking-[0.13em] uppercase";
  const muted = "opacity-70";

  const railCard = (card: Card, index: number) => {
    const box = (kind: string, extra?: string) =>
      cn(
        kind,
        "ambient-rise flex h-[240px] min-w-0 flex-col gap-2 overflow-hidden rounded-[28px] p-6 backdrop-blur-md max-md:h-[180px] max-md:p-5",
        extra,
      );
    const rise = { animationDelay: `${300 + index * 140}ms` };
    if (card === "brief" && data.brief)
      return (
        <section key={card} className={box("ambient-card")} style={rise}>
          <span className={kicker} style={{ color: night ? undefined : data.brief.color }}>
            {data.brief.agent} · {stampLabel(Date.parse(data.brief.publishedAt), minute, tz)}
          </span>
          <span className="line-clamp-2 text-xl font-semibold">{data.brief.title}</span>
          <span className={cn("line-clamp-4 text-[15px] leading-snug", muted)}>{data.brief.summary}</span>
        </section>
      );
    if (card === "markets")
      return (
        <section key={card} className={box("ambient-card")} style={rise}>
          <span className={cn(kicker, "ambient-up")}>Markets</span>
          {data.tickers.slice(0, 4).map((t) => (
            <span key={t.symbol} className="flex items-baseline gap-3 text-lg">
              <strong className="w-16 font-semibold">{t.symbol}</strong>
              <span className={cn("flex-1 text-right tabular-nums max-md:hidden", muted)}>{t.price}</span>
              <span
                className={cn(
                  "ambient-tint w-20 text-right font-semibold tabular-nums max-md:flex-1",
                  t.direction === "up" && "ambient-up",
                  t.direction === "down" && "ambient-down",
                )}
              >
                {t.change}
              </span>
            </span>
          ))}
        </section>
      );
    if (card === "metrics")
      return (
        <section key={card} className={box("ambient-card")} style={rise}>
          <span className={cn(kicker, "ambient-later")}>Metrics</span>
          {data.metrics.slice(0, 4).map((m) => (
            <span key={m.key} className="flex items-baseline gap-3 text-lg">
              <span className={cn("min-w-0 flex-1 truncate text-[15px]", muted)}>{m.label}</span>
              <span className="shrink-0 font-semibold tabular-nums">{m.valueLabel}</span>
              <span
                className={cn(
                  "ambient-tint w-16 shrink-0 text-right text-[14px] font-semibold tabular-nums max-md:hidden",
                  m.good === true && "ambient-up",
                  m.good === false && "ambient-down",
                )}
              >
                {m.deltaPct != null ? `${m.deltaPct > 0 ? "+" : m.deltaPct < 0 ? "−" : ""}${Math.abs(m.deltaPct).toFixed(1)}%` : m.deltaLabel}
              </span>
            </span>
          ))}
        </section>
      );
    if (card === "blocked") {
      const p = data.blocked[0];
      return (
        <section key={card} className={box("ambient-alert")} style={rise}>
          <span className={cn(kicker, "ambient-alert-kicker")}>Needs you</span>
          <span className="line-clamp-2 text-xl font-semibold">
            {data.blocked.length > 1 ? `${p.name} and ${data.blocked.length - 1} more are blocked` : `${p.name} is blocked`}
          </span>
          <span className={cn("line-clamp-3 text-[15px] leading-snug", muted)}>
            {[p.next, p.progress != null ? `${Math.round(p.progress)}% done` : ""].filter(Boolean).join(" · ")}
          </span>
        </section>
      );
    }
    if (card === "pulse" && data.hero)
      return (
        <section key={card} className={box("ambient-card", data.hero.imageUrl ? "p-0 max-md:p-0" : undefined)} style={rise}>
          {data.hero.imageUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={data.hero.imageUrl}
              alt=""
              className={cn("ambient-tint h-[46%] w-full object-cover", night && "opacity-70")}
              style={{ background: data.hero.color }}
            />
          ) : null}
          <span className={cn("flex min-h-0 flex-col gap-1.5", data.hero.imageUrl && "px-5 pb-5 pt-1")}>
            <span className={kicker} style={{ color: night ? undefined : data.hero.color }}>
              {data.hero.source} · {data.hero.count} stories
            </span>
            <span className="line-clamp-2 text-xl font-semibold">{data.hero.headline}</span>
            {!data.hero.imageUrl ? <span className={cn("line-clamp-3 text-[15px] leading-snug", muted)}>{data.hero.takeaway}</span> : null}
          </span>
        </section>
      );
    if (card === "later")
      return (
        <section key={card} className={box("ambient-card")} style={rise}>
          <span className={cn(kicker, "ambient-later")}>Later today</span>
          {todays.slice(3, 7).map((e) => (
            <span key={e.id} className="flex items-center gap-3 text-[15px]">
              <span className="h-5 w-1 rounded-full" style={{ background: e.color }} />
              <span className={cn("w-16 tabular-nums", muted)}>{at(e.starts_at)}</span>
              <span className="truncate font-medium">{e.title}</span>
            </span>
          ))}
        </section>
      );
    return null;
  };

  return (
    <main
      className={cn("ambient fixed inset-0 cursor-pointer overflow-hidden select-none", night && "ambient-night")}
      onClick={() => router.push("/today")}
      aria-label="Ambient view. Click or press any key to go back."
    >
      {sky ? (
        <SkyBackdrop className="absolute inset-0" sky={sky} dark={night} canvas={["--ambient-canvas-day", "--ambient-canvas-night"]} maxFps={15} fade={90} />
      ) : (
        <MeshGradient className="absolute inset-0" dark={night} rings={2} resolution={0.5} maxFps={15} fade={90} />
      )}
      {auroraUp ? (
        <div
          className="ambient-aurora pointer-events-none absolute inset-0"
          aria-hidden="true"
          onTransitionEnd={(e) => {
            if (e.target === e.currentTarget && e.propertyName === "opacity") setAuroraFaded(!night);
          }}
        >
          <GlowAurora
            dark
            height={0.36}
            amplitude={1.1}
            blend={0.7}
            layers={2}
            opacity={0.3}
            speed={0.35}
            mouseInteraction={false}
            resolution={0.5}
            maxFps={15}
            paused={!night && auroraFaded}
          />
        </div>
      ) : null}
      <div className="film-grain" aria-hidden="true" />

      <div
        className="relative flex h-full flex-col justify-between px-[clamp(24px,5vw,72px)] py-[clamp(24px,5vh,64px)]"
        style={{ transform: `translate(${shift.x}px, ${shift.y}px)`, transition: "transform 4s ease-in-out" } as CSSProperties}
      >
        <div className={cn(!cards.length && "my-auto")}>
          <p className="flex items-baseline gap-3" suppressHydrationWarning>
            <span className="text-[clamp(96px,15vw,220px)] leading-[0.92] font-light tracking-[-0.04em] tabular-nums">{clock.time}</span>
            <span className="text-[clamp(20px,2.4vw,34px)] opacity-70">{clock.ampm}</span>
          </p>
          <p className="mt-2 text-[clamp(20px,2.4vw,32px)]" suppressHydrationWarning>
            {clock.date}
          </p>
          {/* What McFly noticed, one line at a time: each line, as its turn
              comes, resolves out of its own letters (React Bits'
              DecryptedText), and reads whole to a screen reader. */}
          {noticed.length && noticing >= 0 ? (
            <p className="mt-3 flex min-w-0 items-center gap-2.5 text-[clamp(16px,1.6vw,22px)] opacity-80">
              <span className="sr-only">McFly noticed: </span>
              <SparklesIcon className="size-[0.85em] shrink-0" aria-hidden="true" />
              <span className="min-w-0 truncate">
                <DecryptedText key={noticed[noticing].id} text={noticed[noticing].title} animateOn="view" sequential speed={28} useOriginalCharsOnly encryptedClassName="opacity-60" />
              </span>
            </p>
          ) : null}
          {nextLine ? (
            <p className="mt-6 truncate text-[clamp(20px,2.4vw,32px)] font-semibold" suppressHydrationWarning>
              {nextLine}
            </p>
          ) : null}
          {thenLine ? <p className="truncate text-[clamp(16px,1.7vw,22px)] opacity-75 max-md:hidden">{thenLine}</p> : null}
        </div>

        {cards.length ? (
          <div className="grid grid-cols-4 gap-4 max-xl:grid-cols-3 max-xl:[&>*:nth-child(4)]:hidden max-lg:grid-cols-2 max-lg:[&>*:nth-child(3)]:hidden">
            {[...pinned, ...rail.shown].slice(0, 4).map((card, i) => (
              // The fade is on a wrapper: the cards' own opacity waits out
              // the night's cross-fade (globals.css .ambient-card).
              <div key={card} className={cn("min-w-0 transition-opacity duration-700 ease-in-out", rail.fading && card !== "blocked" && "opacity-0")}>
                {railCard(card, i)}
              </div>
            ))}
          </div>
        ) : null}
      </div>
    </main>
  );
}
