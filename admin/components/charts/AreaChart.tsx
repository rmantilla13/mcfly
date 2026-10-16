"use client";

import { cn } from "cn";
import { type KeyboardEvent, type PointerEvent, useId, useMemo, useState } from "react";
import { areaPath, chartPoints, formatValue, type NumberFormat, pointTimeLabel, seriesRange, smoothPath } from "@/lib/widgets";
import styles from "./charts.module.css";
import { type ChartTone, toneProps } from "./tone";

// A larger trend: a smooth line over a soft fill, dashed guides at the high
// and the low, and the newest value at the end. Pointing (or a finger, or
// the arrow keys) moves a crosshair from point to point with the value in a
// bubble. Points are plain numbers or {t, v} with t an ISO time or epoch
// ms; the format is data (lib/widgets.ts NumberFormat), so a server page
// can pass it. The SVG stretches to the card's width (a viewBox and a
// non-scaling stroke) and everything round or textual is HTML on top, so
// the server's render is already the right shape.

export type AreaPoint = { t: string | number; v: number };

const W = 600; // viewBox units across; only the proportions matter

export function AreaChart({
  points,
  tone = "neutral",
  color,
  height = 160,
  labels = true,
  label,
  timeZone,
  className,
  ...format
}: NumberFormat & {
  points: (AreaPoint | number)[];
  tone?: ChartTone;
  // An agent's colour; wins over `tone` when it is one (cssColor).
  color?: string | null;
  // Pixels tall, labels included.
  height?: number;
  // The high and low guides and the newest value.
  labels?: boolean;
  // What the chart shows, for screen readers and the crosshair's announcements.
  label?: string;
  // For the times under the crosshair; UTC like the rest of the console.
  timeZone?: string;
  className?: string;
}) {
  const fillId = `area-${useId().replace(/[^\w-]/g, "")}`;
  const [active, setActive] = useState<number | null>(null);
  const { className: toneClass, style } = toneProps(tone, color);

  // Room above the line for the high label and below for the low one.
  const top = labels ? 24 : 6;
  const bottom = labels ? 22 : 0;
  const plotH = Math.max(8, height - top - bottom);

  const chart = useMemo(() => {
    const values: number[] = [];
    const times: (number | null)[] = [];
    for (const p of points) {
      const v = typeof p === "number" ? p : p?.v;
      if (typeof v !== "number" || !Number.isFinite(v)) continue;
      const t = typeof p === "number" ? null : typeof p.t === "number" ? p.t : Date.parse(p.t);
      values.push(v);
      times.push(t !== null && Number.isFinite(t) ? t : null);
    }
    const known = times.filter((t): t is number => t !== null);
    return {
      values,
      times,
      span: known.length > 1 ? Math.max(...known) - Math.min(...known) : 0,
      line: smoothPath(values, W, plotH, 0),
      area: areaPath(values, W, plotH, 0, plotH + bottom),
      at: chartPoints(values, W, plotH, 0),
      range: seriesRange(values),
    };
  }, [points, plotH, bottom]);

  const { values, times, at, range } = chart;
  const n = values.length;
  const fmt = (v: number) => formatValue(v, format);

  if (n === 0) {
    return (
      <div className={cn("grid w-full place-items-center text-sm text-muted-foreground", className)} style={{ height }}>
        No points.
      </div>
    );
  }

  const last = n - 1;
  const xPct = (i: number) => (n === 1 ? 50 : (at[i].x / W) * 100);
  const yPx = (i: number) => top + at[i].y;
  const timeOf = (i: number) => (times[i] !== null ? pointTimeLabel(times[i] as number, chart.span, timeZone) : "");
  const flat = !range || range.min === range.max;
  const summary = [label ?? "Chart", `latest ${fmt(values[last])}`, flat ? null : `high ${fmt(range.max)}`, flat ? null : `low ${fmt(range.min)}`]
    .filter(Boolean)
    .join(", ");

  const indexAt = (e: PointerEvent<HTMLDivElement>) => {
    const box = e.currentTarget.getBoundingClientRect();
    const frac = box.width > 0 ? (e.clientX - box.left) / box.width : 1;
    return Math.max(0, Math.min(last, Math.round(frac * last)));
  };
  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    const from = active ?? last;
    const next =
      e.key === "ArrowLeft" ? from - 1 : e.key === "ArrowRight" ? from + 1 : e.key === "Home" ? 0 : e.key === "End" ? last : null;
    if (e.key === "Escape") setActive(null);
    if (next === null) return;
    e.preventDefault();
    setActive(Math.max(0, Math.min(last, next)));
  };

  // The newest value sits in whichever gutter is nearer its point, at the right.
  const lastAbove = at[last].y <= plotH / 2;
  const hover = active !== null && active <= last ? active : null;
  const bubbleAbove = hover !== null && yPx(hover) >= 52;
  const bubbleAlign = hover === null ? "" : xPct(hover) < 14 ? "translate-x-[-10px]" : xPct(hover) > 86 ? "-translate-x-[calc(100%-10px)]" : "-translate-x-1/2";

  return (
    <div
      className={cn("relative w-full touch-pan-y outline-none select-none focus-visible:ring-2 focus-visible:ring-ring/50 rounded-md", toneClass, className)}
      style={{ ...style, height }}
      role="group"
      aria-roledescription="chart"
      aria-label={summary}
      tabIndex={0}
      onPointerMove={(e) => setActive(indexAt(e))}
      onPointerDown={(e) => setActive(indexAt(e))}
      onPointerLeave={() => setActive(null)}
      onKeyDown={onKeyDown}
      onBlur={() => setActive(null)}
    >
      <svg viewBox={`0 0 ${W} ${height}`} preserveAspectRatio="none" className={cn("absolute inset-0 size-full", styles.reveal)} aria-hidden="true">
        <defs>
          {/* In the path's own space, which the group below has already
              moved down by `top`: 28% at the top of the plot, 0 at the base. */}
          <linearGradient id={fillId} gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" y2={plotH + bottom}>
            <stop offset="0" stopColor="currentColor" stopOpacity={0.28} />
            <stop offset="1" stopColor="currentColor" stopOpacity={0} />
          </linearGradient>
        </defs>
        <g transform={`translate(0 ${top})`}>
          <path d={chart.area} fill={`url(#${fillId})`} />
          <path d={chart.line} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" vectorEffect="non-scaling-stroke" />
        </g>
      </svg>

      {labels && !flat ? (
        <>
          <div className={cn("pointer-events-none absolute inset-x-0 border-t border-dashed border-foreground/15", styles.late)} style={{ top }} aria-hidden="true" />
          <div className={cn("pointer-events-none absolute inset-x-0 border-t border-dashed border-foreground/15", styles.late)} style={{ top: top + plotH }} aria-hidden="true" />
          <span className={cn("pointer-events-none absolute left-0 text-[11px] leading-none text-muted-foreground tabular-nums", styles.late)} style={{ top: top - 15 }} aria-hidden="true">
            High <span className="font-medium text-foreground">{fmt(range.max)}</span>
          </span>
          <span className={cn("pointer-events-none absolute left-0 text-[11px] leading-none text-muted-foreground tabular-nums", styles.late)} style={{ top: top + plotH + 6 }} aria-hidden="true">
            Low <span className="font-medium text-foreground">{fmt(range.min)}</span>
          </span>
        </>
      ) : null}
      {labels ? (
        <span
          className={cn("pointer-events-none absolute right-0 text-[11px] leading-none font-semibold text-foreground tabular-nums", styles.late)}
          style={lastAbove ? { top: top - 15 } : { top: top + plotH + 6 }}
          aria-hidden="true"
        >
          {fmt(values[last])}
        </span>
      ) : null}

      {/* The newest point. */}
      <span
        className={cn("pointer-events-none absolute size-2 rounded-full bg-current ring-2 ring-card", styles.pop)}
        style={{ left: `${xPct(last)}%`, top: yPx(last) }}
        aria-hidden="true"
      />

      {hover !== null ? (
        <>
          <div
            className="pointer-events-none absolute w-px -translate-x-1/2 bg-foreground/25"
            style={{ left: `${xPct(hover)}%`, top: top - 4, bottom: 0 }}
            aria-hidden="true"
          />
          <span
            className="pointer-events-none absolute size-2.5 -translate-x-1/2 -translate-y-1/2 rounded-full bg-current ring-2 ring-card"
            style={{ left: `${xPct(hover)}%`, top: yPx(hover) }}
            aria-hidden="true"
          />
          <div
            className={cn(
              "pointer-events-none absolute z-10 flex flex-col gap-0.5 rounded-lg bg-popover px-2.5 py-1.5 text-xs whitespace-nowrap text-popover-foreground shadow-md ring-1 ring-foreground/10",
              bubbleAlign,
              bubbleAbove ? "-translate-y-full" : "",
            )}
            style={{ left: `${xPct(hover)}%`, top: bubbleAbove ? yPx(hover) - 10 : yPx(hover) + 12 }}
            aria-hidden="true"
          >
            <span className="font-semibold tabular-nums">{fmt(values[hover])}</span>
            {timeOf(hover) ? <span className="text-muted-foreground">{timeOf(hover)}</span> : null}
          </div>
        </>
      ) : null}

      {/* What the arrow keys land on, read out. */}
      <span className="sr-only" aria-live="polite">
        {hover !== null ? [fmt(values[hover]), timeOf(hover)].filter(Boolean).join(", ") : ""}
      </span>
    </div>
  );
}
