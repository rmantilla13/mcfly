import { cn } from "cn";
import type { CSSProperties } from "react";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { cssColor } from "@/lib/format";
import { barTotals, formatValue, type NumberFormat } from "@/lib/widgets";
import styles from "./charts.module.css";

// A compact strip of stacked bars: a day of pushes by the hour, stacked by
// feed. Bars share one scale (the tallest, or `max`), series stack from the
// baseline in order, and each series takes --chart-1…5 in turn unless it
// brings its own colour (an agent's, through cssColor). A hairline gap
// between the pieces keeps neighbouring colours apart even where two
// tokens are close in lightness. `alert` puts a red tick over a bar (pushes
// that were refused). Pointing at a bar shows its numbers in a tooltip,
// which is portalled so a Card's overflow-hidden can't cut it off. A server
// component; the bars grow in with CSS.

export type BarStripBar = {
  // "2 PM", "Tue": the bar's name in its tip and in the summary.
  label?: string;
  // One value per series, in `series` order. Nothing below zero is drawn.
  values: number[];
  alert?: number;
};

export type BarStripSeries = { label: string; color?: string | null };

export function BarStrip({
  bars,
  series = [],
  height = 56,
  max,
  legend = false,
  label,
  alertLabel = "refused",
  className,
  ...format
}: NumberFormat & {
  bars: BarStripBar[];
  series?: BarStripSeries[];
  // Pixels tall.
  height?: number;
  // The value at full height; the tallest bar by default.
  max?: number;
  legend?: boolean;
  // What the strip counts ("Pushes, last 24h"), for screen readers.
  label?: string;
  // The word after an alert count in a tip: "2 refused".
  alertLabel?: string;
  className?: string;
}) {
  const { totals, max: tallest } = barTotals(bars);
  const top = max !== undefined && max > 0 ? max : tallest;
  const colorOf = (i: number) => cssColor(series[i]?.color) ?? `var(--chart-${(i % 5) + 1})`;
  const nameOf = (i: number) => series[i]?.label ?? `Series ${i + 1}`;
  const fmt = (n: number) => formatValue(n, format);

  const sum = totals.reduce((a, b) => a + b, 0);
  const peak = totals.indexOf(tallest);
  const summary = [
    label ?? "Bars",
    `${fmt(sum)} in all`,
    peak >= 0 && tallest > 0 ? `most ${bars[peak].label ? `at ${bars[peak].label}` : "in one bar"}: ${fmt(tallest)}` : null,
  ]
    .filter(Boolean)
    .join(", ");
  const shown = new Set(bars.flatMap((b) => b.values.flatMap((v, i) => (v > 0 ? [i] : []))));

  // Headroom for an alert tick over a full-height bar, so the tick never
  // eats into the bar (which would break the shared scale) or the header.
  const ticked = bars.some((b) => (b.alert ?? 0) > 0);

  return (
    <div className={cn("flex flex-col gap-2", className)}>
      <div
        className={cn(styles.strip, "flex items-end gap-[3px]")}
        style={{ height, paddingTop: ticked ? 5 : undefined }}
        role="img"
        aria-label={summary}
      >
        {bars.map((bar, i) => {
          const total = totals[i];
          const pct = top > 0 ? Math.min(100, (total / top) * 100) : 0;
          return (
            <Tooltip key={i}>
              <TooltipTrigger asChild>
                <div className={cn(styles.col, "relative flex h-full min-w-0 flex-1 flex-col justify-end")}>
                  {total > 0 ? (
                    <div
                      className={cn(styles.bar, "flex min-h-[3px] flex-col-reverse gap-px overflow-hidden rounded-[3px]")}
                      style={{ height: `${pct}%`, "--i": i } as CSSProperties}
                    >
                      {bar.values.map((v, s) =>
                        Number.isFinite(v) && v > 0 ? <span key={s} className="min-h-px basis-0" style={{ flexGrow: v, background: colorOf(s) }} /> : null,
                      )}
                    </div>
                  ) : (
                    // An empty hour still has its place on the line.
                    <span className="h-0.5 w-full shrink-0 rounded-full bg-foreground/10" />
                  )}
                  {bar.alert ? (
                    // Out of flow, 2px over the bar's top (or the empty stub).
                    <span
                      className={cn(styles.tick, "absolute inset-x-0 h-[3px] rounded-full bg-destructive")}
                      style={{ bottom: total > 0 ? `calc(max(${pct}%, 3px) + 2px)` : 4, "--i": i } as CSSProperties}
                    />
                  ) : null}
                </div>
              </TooltipTrigger>
              {/* The console's tooltip, inverted like every other one. Its
                  zoom and slide are attribute variants, which outrank a plain
                  motion-reduce: hence the important form. */}
              <TooltipContent
                side="top"
                sideOffset={6}
                className="min-w-28 flex-col items-stretch gap-1 rounded-lg px-2.5 py-2 whitespace-nowrap motion-reduce:animate-none!"
              >
                <span className="flex items-baseline justify-between gap-3">
                  <span className="text-background/70">{bar.label ?? `#${i + 1}`}</span>
                  <span className="font-semibold tabular-nums">{fmt(total)}</span>
                </span>
                {bar.values.map((v, s) =>
                  Number.isFinite(v) && v > 0 ? (
                    <span key={s} className="flex items-center gap-1.5">
                      <span className="size-2 shrink-0 rounded-[2px]" style={{ background: colorOf(s) }} />
                      <span className="flex-1 text-background/70">{nameOf(s)}</span>
                      <span className="tabular-nums">{fmt(v)}</span>
                    </span>
                  ) : null,
                )}
                {bar.alert ? (
                  <span className="flex items-center gap-1.5">
                    <span className="size-2 shrink-0 rounded-full bg-destructive" />
                    <span className="tabular-nums">
                      {fmt(bar.alert)} {alertLabel}
                    </span>
                  </span>
                ) : null}
              </TooltipContent>
            </Tooltip>
          );
        })}
      </div>
      {legend && shown.size > 0 ? (
        <ul className="flex flex-wrap gap-x-3.5 gap-y-1 text-xs text-muted-foreground">
          {[...shown]
            .sort((a, b) => a - b)
            .map((i) => (
              <li key={i} className="inline-flex items-center gap-1.5">
                <span className="size-2 rounded-[2px]" style={{ background: colorOf(i) }} aria-hidden="true" />
                {nameOf(i)}
              </li>
            ))}
        </ul>
      ) : null}
    </div>
  );
}
