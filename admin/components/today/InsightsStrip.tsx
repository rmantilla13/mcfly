"use client";

import { cn } from "cn";
import {
  ActivityIcon,
  BellOffIcon,
  CalendarClockIcon,
  CircleCheckIcon,
  FileTextIcon,
  NewspaperIcon,
  OctagonAlertIcon,
  SparklesIcon,
  TrendingDownIcon,
  TrendingUpIcon,
  TriangleAlertIcon,
} from "lucide-react";
import Link from "next/link";
import { useEffect, useLayoutEffect, useRef, type CSSProperties } from "react";
import { cssColor } from "@/lib/format";
import type { Insight, InsightKind, InsightTone } from "@/lib/insights";
import { Tile, TileHead } from "./Tile";
import styles from "./today.module.css";

// "McFly noticed": what stands out right now (lib/insights.ts), ranked, the
// first one larger. Each card goes to its page; one with a question offers
// to ask McFly about it (/ask?q=…, asked on arrival). The insights are
// worked out on the server from the same rows as the page, no model call.
//
// The list re-renders each minute with the page. Ids are stable (kind:thing),
// so a card that stays keeps its place in the DOM: only a new one slides in,
// and one that changes rank glides to its new spot (measured before and
// after, then animated back from where it was).

const TONE: Record<InsightTone, string> = {
  good: "var(--success)",
  bad: "var(--destructive)",
  warn: "var(--warning)",
  neutral: "var(--primary)",
};

const ICON: Record<InsightKind, typeof SparklesIcon> = {
  blocked: OctagonAlertIcon,
  metric: ActivityIcon,
  mover: TrendingUpIcon,
  event: CalendarClockIcon,
  brief: FileTextIcon,
  pulse: NewspaperIcon,
  silent: BellOffIcon,
  errors: TriangleAlertIcon,
};

export function InsightsStrip({ insights, index, className }: { insights: Insight[]; index: number; className?: string }) {
  const items = useRef(new Map<string, HTMLElement>());
  const list = useRef<HTMLOListElement>(null);
  const last = useRef(new Map<string, { x: number; y: number }>());
  const order = insights.map((i) => i.id).join("|");
  const n = insights.length;
  const listed = n > 0; // the list is there to watch (else the all-clear line)

  // A card that changed rank glides from where it was. Positions are the
  // layout's own (offsetLeft/Top), not the box on screen: a card still
  // sliding in, or one mid-glide, would otherwise be measured off its spot.
  useLayoutEffect(() => {
    if (!list.current) return;
    const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const now = new Map<string, { x: number; y: number }>();
    for (const [id, el] of items.current) {
      const at = { x: el.offsetLeft, y: el.offsetTop };
      now.set(id, at);
      const was = last.current.get(id);
      if (!was || still) continue;
      const dx = was.x - at.x;
      const dy = was.y - at.y;
      if (Math.abs(dx) < 1 && Math.abs(dy) < 1) continue;
      el.animate([{ translate: `${dx}px ${dy}px` }, { translate: "0 0" }], { duration: 450, easing: "cubic-bezier(0.2, 0.8, 0.2, 1)" });
    }
    last.current = now;
  }, [order]);

  // The list reflowing between refreshes (a narrower window, the grid going
  // to one column) moves the cards with nothing to animate: note where they
  // are now, so the next reorder glides from there and not from before.
  useEffect(() => {
    const box = list.current;
    if (!box) return;
    const watch = new ResizeObserver(() => {
      const now = new Map<string, { x: number; y: number }>();
      for (const [id, el] of items.current) now.set(id, { x: el.offsetLeft, y: el.offsetTop });
      last.current = now;
    });
    watch.observe(box);
    return () => watch.disconnect();
  }, [listed]);

  return (
    <Tile index={index} label="McFly noticed" className={cn("gap-4 p-5", className)}>
      <TileHead icon={<SparklesIcon />}>McFly noticed</TileHead>
      {n === 0 ? (
        <p className="flex flex-1 items-center gap-3 rounded-[20px] bg-muted/70 px-4 py-5 text-[15px] text-muted-foreground">
          <CircleCheckIcon className="size-5 shrink-0 text-success" aria-hidden="true" />
          Nothing stands out right now: nothing blocked, nothing far off its usual, nothing about to start.
        </p>
      ) : (
        <ol ref={list} className="grid gap-2.5 sm:grid-cols-2">
          {insights.map((insight, i) => {
            // The first is the headline; an odd one out at the end takes the row.
            const wide = i === 0 || (i === n - 1 && (n - 1) % 2 === 1);
            return (
              <InsightCard
                key={insight.id}
                insight={insight}
                rank={i}
                wide={wide}
                ref={(el) => {
                  if (el) items.current.set(insight.id, el);
                  else items.current.delete(insight.id);
                }}
              />
            );
          })}
        </ol>
      )}
    </Tile>
  );
}

function InsightCard({ insight: i, rank, wide, ref }: { insight: Insight; rank: number; wide: boolean; ref: (el: HTMLLIElement | null) => void }) {
  const color = (i.tone === "neutral" && cssColor(i.color)) || TONE[i.tone];
  const Icon = i.kind === "mover" && i.tone === "bad" ? TrendingDownIcon : (ICON[i.kind] ?? TriangleAlertIcon);
  const lead = rank === 0;
  return (
    <li
      ref={ref}
      className={cn(
        "relative flex min-w-0 items-start gap-3 rounded-[20px] p-3.5 ring-1 ring-foreground/[0.04] transition-colors",
        !lead && "bg-muted/70",
        i.href && "hover:ring-foreground/15",
        wide && "sm:col-span-2",
        styles.slide,
      )}
      style={{ "--i": rank, ...(lead ? { backgroundColor: `color-mix(in oklab, ${color} 9%, var(--card))` } : {}) } as CSSProperties}
    >
      <span
        className={cn("grid shrink-0 place-items-center rounded-full", lead ? "size-10" : "size-8")}
        style={{ color, backgroundColor: `color-mix(in oklab, ${color} 15%, transparent)` }}
        aria-hidden="true"
      >
        <Icon className={lead ? "size-5" : "size-4"} />
      </span>
      <span className="min-w-0 flex-1">
        {i.href ? (
          <Link
            href={i.href}
            className={cn(
              "block font-semibold text-foreground no-underline outline-none after:absolute after:inset-0 after:rounded-[inherit] focus-visible:after:ring-2 focus-visible:after:ring-ring",
              lead ? "text-[17px] leading-snug" : "line-clamp-2 text-[15px] leading-snug",
            )}
          >
            {i.title}
          </Link>
        ) : (
          <span className={cn("block font-semibold", lead ? "text-[17px] leading-snug" : "line-clamp-2 text-[15px] leading-snug")}>{i.title}</span>
        )}
        {i.detail ? <span className={cn("mt-0.5 block text-muted-foreground", lead ? "text-sm" : "line-clamp-2 text-[13px]")}>{i.detail}</span> : null}
      </span>
      {i.question ? (
        <Link
          href={`/ask?q=${encodeURIComponent(i.question)}`}
          className="relative z-10 -my-0.5 flex h-8 shrink-0 items-center gap-1.5 self-center rounded-full bg-card px-3 text-[13px] font-medium text-foreground no-underline shadow-xs ring-1 ring-foreground/10 transition-colors hover:bg-accent hover:text-accent-foreground focus-visible:ring-2 focus-visible:ring-ring"
          title={i.question}
          aria-label={`Ask McFly: ${i.question}`}
        >
          <SparklesIcon className="size-3.5" aria-hidden="true" />
          Ask
        </Link>
      ) : null}
    </li>
  );
}
