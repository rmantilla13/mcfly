"use client";

import { CalendarIcon, FileTextIcon, GitCommitHorizontalIcon, NewspaperIcon, TrendingUpIcon, ZapIcon } from "lucide-react";
import { useEffect, useRef, useState, type ReactNode } from "react";
import { GlowAurora } from "@/components/GlowAurora";
import SplitFlapText from "@/components/reactbits/SplitFlapText";

// The sign-in page's living backdrop: the display's glow drifting in three
// blobs, an aurora in the same colours hanging from the top (it leans toward
// the pointer), a light that follows the pointer, and on wide screens a column
// of the kinds of cards agents push, floating past a live clock and a
// split-flap board that flips through what agents report. Everything is
// sample text: nothing here comes from the database before sign-in.
//
// The blobs, cards and ring are CSS (globals.css, "login-" classes), so they
// run off the main thread; the aurora is one WebGL pass (GlowAurora) and the
// board flips with CSS keyframes (components/reactbits). All of it stops under
// prefers-reduced-motion. The pointer light writes two CSS variables at most
// once a frame.

const SAMPLES: { icon: typeof ZapIcon; kicker: string; title: string; color: string }[] = [
  { icon: FileTextIcon, kicker: "Grok · Daily", title: "Morning briefing", color: "#7A64E8" },
  { icon: TrendingUpIcon, kicker: "Markets", title: "NVDA +1.51% · SPY +0.32%", color: "#2E9E6A" },
  { icon: NewspaperIcon, kicker: "Daily Pulse · 6 stories", title: "Today's report is in", color: "#5B7CF5" },
  { icon: CalendarIcon, kicker: "Up next · in 18 min", title: "Standup", color: "#F07F5A" },
  { icon: GitCommitHorizontalIcon, kicker: "McFly", title: "CI green on main", color: "#3DB37A" },
  { icon: ZapIcon, kicker: "Market desk · Alert", title: "TSLA up 4% on deliveries", color: "#F6B94A" },
];

// What the board flips through: the cards' news, as an agent would say it.
const REPORTS = ["BRIEF READY", "NVDA +1.51%", "PULSE: 6 STORIES", "STANDUP IN 18 MIN", "CI GREEN ON MAIN", "TSLA +4.0%"];

function Clock() {
  const [now, setNow] = useState<Date | null>(null);
  useEffect(() => {
    const tick = () => setNow(new Date());
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, []);
  // Rendered after mount only: the server doesn't know the viewer's zone.
  if (!now) return <div className="h-[132px]" aria-hidden="true" />;
  const [time, ampm] = now.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" }).split(" ");
  return (
    <div className="login-rise" style={{ animationDelay: "120ms" }}>
      <p className="flex items-baseline gap-2 text-foreground">
        <span className="text-[104px] leading-none font-light tracking-[-0.05em] tabular-nums">{time}</span>
        <span className="text-xl text-muted-foreground">{ampm}</span>
      </p>
      <p className="mt-1 text-[15px] text-muted-foreground">
        {now.toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric" })}
      </p>
    </div>
  );
}

function SampleCard({ sample, index }: { sample: (typeof SAMPLES)[number]; index: number }) {
  const Icon = sample.icon;
  return (
    <div
      className="login-float flex items-center gap-3.5 rounded-[22px] bg-card/80 px-4 py-3.5 shadow-lg shadow-foreground/5 ring-1 ring-foreground/5 backdrop-blur-md"
      style={{ animationDelay: `${index * -2.7}s`, marginLeft: `${(index % 3) * 28}px` }}
    >
      <span className="relative grid size-10 shrink-0 place-items-center rounded-full" style={{ color: sample.color }}>
        <span className="absolute inset-0 rounded-full opacity-15" style={{ background: sample.color }} />
        <Icon className="relative size-[18px]" />
      </span>
      <span className="min-w-0">
        <span className="block truncate text-[11px] font-bold tracking-[0.1em] uppercase" style={{ color: sample.color }}>
          {sample.kicker}
        </span>
        <span className="block truncate text-[15px] font-semibold text-foreground">{sample.title}</span>
      </span>
    </div>
  );
}

export function LoginScene({ children }: { children: ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);

  // The pointer light: two CSS variables, written at most once a frame.
  useEffect(() => {
    const el = ref.current;
    if (!el || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    let frame = 0;
    const move = (e: PointerEvent) => {
      if (frame) return;
      frame = requestAnimationFrame(() => {
        frame = 0;
        el.style.setProperty("--login-x", `${e.clientX}px`);
        el.style.setProperty("--login-y", `${e.clientY}px`);
      });
    };
    window.addEventListener("pointermove", move, { passive: true });
    return () => {
      window.removeEventListener("pointermove", move);
      cancelAnimationFrame(frame);
    };
  }, []);

  return (
    <div ref={ref} className="login-scene relative min-h-screen overflow-hidden">
      <div className="login-blob login-blob-1" aria-hidden="true" />
      <div className="login-blob login-blob-2" aria-hidden="true" />
      <div className="login-blob login-blob-3" aria-hidden="true" />
      <div className="pointer-events-none absolute inset-0" aria-hidden="true">
        <GlowAurora height={0.3} amplitude={1.2} blend={0.6} layers={2} opacity={0.75} speed={0.55} dpr={1} />
      </div>
      <div className="login-spotlight" aria-hidden="true" />
      <div className="film-grain" aria-hidden="true" />

      <div className="relative mx-auto grid min-h-screen max-w-[1200px] grid-cols-[minmax(0,1.1fr)_minmax(0,1fr)] items-center gap-16 px-10 py-12 max-lg:grid-cols-1 max-lg:gap-8 max-md:px-4">
        {/* Wide screens: what McFly is, alive. */}
        <section className="flex flex-col gap-10 max-lg:hidden" aria-hidden="true">
          <Clock />
          <h2 className="login-rise text-[44px] leading-[1.05] font-semibold tracking-tight text-foreground" style={{ animationDelay: "220ms" }}>
            Your agents,
            <br />
            <span className="login-shimmer">on one screen.</span>
          </h2>
          <div className="login-rise" style={{ animationDelay: "320ms" }}>
            <SplitFlapText
              words={REPORTS}
              padTo={17}
              fontSize={24}
              gap={3}
              tileRadius={5}
              tileColor="#1B1A1F"
              textColor="#F3F2EF"
              glare={0.4}
              charset="ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+%."
              flipsPerChar={5}
              flipDuration={0.09}
              stagger={0.035}
              cycleDelay={3200}
              depth={0.4}
            />
          </div>
          <div className="relative flex h-[300px] flex-col gap-3 overflow-hidden [mask-image:linear-gradient(transparent,black_18%,black_82%,transparent)]">
            <div className="login-drift flex flex-col gap-3">
              {[...SAMPLES, ...SAMPLES].map((s, i) => (
                <SampleCard key={i} sample={s} index={i % SAMPLES.length} />
              ))}
            </div>
          </div>
        </section>

        {/* The sign-in card, on a slowly turning glow border. */}
        <div className="login-rise flex flex-col items-center gap-5" style={{ animationDelay: "60ms" }}>
          <div className="login-ring w-full max-w-[420px] rounded-[calc(var(--radius)*1.8+2px)] p-[2px]">
            <div className="login-voice relative rounded-[calc(var(--radius)*1.8)] bg-card">{children}</div>
          </div>
          <p className="mt-6 text-center text-[13px] text-muted-foreground">Access is limited to accounts listed in platform_admins.</p>
        </div>
      </div>
    </div>
  );
}
