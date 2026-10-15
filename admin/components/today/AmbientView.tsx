"use client";

import { cn } from "cn";
import { useRouter } from "next/navigation";
import { useEffect, useState, type CSSProperties } from "react";
import type { TodayData } from "@/lib/today-data";
import { formatClock, untilLabel } from "@/lib/today";
import { clockParts, useLiveRefresh, useNow } from "./TodayView";

// The display's ambient screen saver, in a browser: readable from across
// the room on a spare monitor or a tablet. The gradient drifts, the clock
// and what's next sit on it, and a rail of cards from the feeds runs along
// the bottom. Any click or key goes back to Today. The whole composition
// moves a few pixels every minute against burn-in; cards dim at night.

function hourIn(ms: number, timeZone: string): number {
  return Number(new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric", hourCycle: "h23" }).format(new Date(ms)));
}

type Card = "brief" | "markets" | "blocked" | "pulse" | "later";

export function AmbientView({ data }: { data: TodayData }) {
  useLiveRefresh();
  const router = useRouter();
  const now = useNow(data.nowMs, 1_000);
  const minute = Math.floor(now / 60_000) * 60_000;
  const tz = data.timeZone;
  const clock = clockParts(now, tz);
  const hour = hourIn(now, tz);
  const night = hour >= 21 || hour < 6;

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
  if (todays.length > 3) cards.push("later");

  const cardStyle = cn(
    "flex h-[240px] min-w-0 flex-col gap-2 overflow-hidden rounded-[28px] p-6 backdrop-blur-md max-md:h-[180px] max-md:p-5",
    night ? "bg-black/40 text-white/80" : "bg-white/85 text-[#1D1B24]",
  );
  const kicker = "text-xs font-bold tracking-[0.13em] uppercase";
  const muted = night ? "text-white/55" : "text-[#4A4555]";

  return (
    <main
      className={cn("ambient fixed inset-0 cursor-pointer overflow-hidden select-none", night && "ambient-night")}
      onClick={() => router.push("/today")}
      aria-label="Ambient view. Click or press any key to go back."
    >
      <div className="ambient-blob ambient-blob-1" aria-hidden="true" />
      <div className="ambient-blob ambient-blob-2" aria-hidden="true" />
      <div className="ambient-blob ambient-blob-3" aria-hidden="true" />

      <div
        className={cn("relative flex h-full flex-col justify-between px-[clamp(24px,5vw,72px)] py-[clamp(24px,5vh,64px)]", night ? "text-white/85" : "text-[#2A2218]")}
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
          {nextLine ? (
            <p className="mt-6 truncate text-[clamp(20px,2.4vw,32px)] font-semibold" suppressHydrationWarning>
              {nextLine}
            </p>
          ) : null}
          {thenLine ? <p className="truncate text-[clamp(16px,1.7vw,22px)] opacity-75 max-md:hidden">{thenLine}</p> : null}
        </div>

        {cards.length ? (
          <div className="grid grid-cols-4 gap-4 max-xl:grid-cols-3 max-xl:[&>*:nth-child(4)]:hidden max-lg:grid-cols-2 max-lg:[&>*:nth-child(3)]:hidden">
            {cards.slice(0, 4).map((card) => {
              if (card === "brief" && data.brief)
                return (
                  <section key={card} className={cardStyle}>
                    <span className={kicker} style={{ color: night ? undefined : data.brief.color }}>
                      {data.brief.agent} · {at(data.brief.publishedAt)}
                    </span>
                    <span className="line-clamp-2 text-xl font-semibold">{data.brief.title}</span>
                    <span className={cn("line-clamp-4 text-[15px] leading-snug", muted)}>{data.brief.summary}</span>
                  </section>
                );
              if (card === "markets")
                return (
                  <section key={card} className={cardStyle}>
                    <span className={cn(kicker, !night && "text-[#1C7A4E]")}>Markets</span>
                    {data.tickers.slice(0, 4).map((t) => (
                      <span key={t.symbol} className="flex items-baseline gap-3 text-lg">
                        <strong className="w-16 font-semibold">{t.symbol}</strong>
                        <span className={cn("flex-1 text-right tabular-nums max-md:hidden", muted)}>{t.price}</span>
                        <span
                          className={cn(
                            "w-20 text-right font-semibold tabular-nums max-md:flex-1",
                            !night && t.direction === "up" && "text-[#1C7A4E]",
                            !night && t.direction === "down" && "text-[#B5432A]",
                          )}
                        >
                          {t.change}
                        </span>
                      </span>
                    ))}
                  </section>
                );
              if (card === "blocked") {
                const p = data.blocked[0];
                return (
                  <section key={card} className={cn(cardStyle, !night && "bg-[#FFE7DF]/90 text-[#3B1D12]")}>
                    <span className={cn(kicker, night ? "text-[#FF9B8A]" : "text-[#B23224]")}>Needs you</span>
                    <span className="line-clamp-2 text-xl font-semibold">
                      {data.blocked.length > 1 ? `${p.name} and ${data.blocked.length - 1} more are blocked` : `${p.name} is blocked`}
                    </span>
                    <span className={cn("line-clamp-3 text-[15px] leading-snug", night ? "text-white/55" : "text-[#5A3426]")}>
                      {[p.next, p.progress != null ? `${Math.round(p.progress)}% done` : ""].filter(Boolean).join(" · ")}
                    </span>
                  </section>
                );
              }
              if (card === "pulse" && data.hero)
                return (
                  <section key={card} className={cn(cardStyle, data.hero.imageUrl && "p-0 max-md:p-0")}>
                    {data.hero.imageUrl ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={data.hero.imageUrl} alt="" className={cn("h-[46%] w-full object-cover", night && "opacity-70")} style={{ background: data.hero.color }} />
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
                  <section key={card} className={cardStyle}>
                    <span className={cn(kicker, !night && "text-primary")}>Later today</span>
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
            })}
          </div>
        ) : null}
      </div>
    </main>
  );
}
