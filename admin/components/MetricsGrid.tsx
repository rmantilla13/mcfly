import { cn } from "cn";
import { GaugeIcon, SparklesIcon } from "lucide-react";
import { AnimatedNumber } from "@/components/AnimatedNumber";
import { EmptyState, Time } from "@/components/bits";
import { RingGauge, Sparkline } from "@/components/charts";
import { AskLink, ChangeChip, Footnote } from "@/components/feed/bits";
import { CARD, rise } from "@/components/feed/styles";
import { metricTile } from "@/lib/feed-layout";
import { ANOMALY_Z, goodDirection } from "@/lib/insights";
import type { SeriesPoint } from "@/lib/series";
import { type TodayMetric, toMetric } from "@/lib/today";
import type { MetricRow } from "@/lib/types";
import { formatMetricValue } from "@/lib/widgets";

// The Metrics tab as tiles, a section per group in the display's order. The
// tile follows the unit (lib/feed-layout.ts metricTile): a percentage is a
// ring, money a big figure over its month, a latency or a count the figure
// with its change and its line. A change is green when it is good news, so
// a falling latency is green (goodDirection), and a value far off its usual
// says so. Hidden metrics are left to the Manage view.

type Tile = { m: MetricRow; t: TodayMetric; kind: ReturnType<typeof metricTile> };

// Static class names, so Tailwind sees every span a group may take.
const SM_SPAN: Record<number, string> = { 1: "sm:col-span-1", 2: "sm:col-span-2" };
const XL_SPAN: Record<number, string> = { 1: "xl:col-span-1", 2: "xl:col-span-2", 3: "xl:col-span-3" };

export function MetricsGrid({ metrics, series }: { metrics: MetricRow[]; series: Record<string, SeriesPoint[]> }) {
  const shown = metrics.filter((m) => !m.hidden && m.value != null);
  const hidden = metrics.filter((m) => m.hidden);
  if (shown.length === 0) {
    return (
      <EmptyState title={metrics.length ? "Every metric is hidden" : "No metrics"} icon={<GaugeIcon />}>
        {metrics.length
          ? "Manage shows them all; switch one back on to see it here and on the display."
          : "Every metric an agent pushes (POST /ingest/metrics) shows up here by group, in display order."}
      </EmptyState>
    );
  }
  // Groups in the order they first come (the RPC sorts by group, then order).
  const groups = new Map<string, Tile[]>();
  for (const m of shown) {
    const name = m.group_name ?? "Ungrouped";
    const tile = { m, t: toMetric(m, series[m.key] ?? []), kind: metricTile(m.unit, m.key) };
    const list = groups.get(name);
    if (list) list.push(tile);
    else groups.set(name, [tile]);
  }
  let index = 0;
  // One grid for the page, each group a section across as many of its
  // columns as its tiles need (a subgrid), so small groups sit side by side
  // instead of each leaving most of a row empty. Its tiles stretch to the
  // row's tallest.
  return (
    <>
      <div className="grid grid-cols-1 gap-x-4 gap-y-7 sm:grid-cols-2 xl:grid-cols-3">
        {[...groups.entries()].map(([name, tiles]) => {
          const span = tiles.reduce((sum, t) => sum + (t.kind === "money" ? 2 : 1), 0);
          return (
            <section key={name} aria-label={name} className={cn("grid grid-cols-subgrid grid-rows-[auto] auto-rows-fr gap-y-3", SM_SPAN[Math.min(2, span)], XL_SPAN[Math.min(3, span)])}>
              <h3 className="col-span-full flex items-center gap-2 px-1 text-xs font-semibold tracking-wider text-muted-foreground uppercase">
                {name}
                <span className="rounded-full bg-foreground/8 px-1.5 font-medium tracking-normal tabular-nums normal-case">{tiles.length}</span>
              </h3>
              {tiles.map((tile) => (
                <MetricTile key={tile.m.key} tile={tile} index={index++} />
              ))}
            </section>
          );
        })}
      </div>
      {hidden.length ? <Footnote>Hidden from the display: {hidden.map((m) => m.label).join(", ")}. Manage lists every metric.</Footnote> : null}
    </>
  );
}

function MetricTile({ tile: { m, t, kind }, index }: { tile: Tile; index: number }) {
  const r = rise(index);
  const change = t.delta ?? t.deltaPct;
  const direction = change == null || change === 0 ? "flat" : change > 0 ? "up" : "down";
  const chipTone = t.good === true ? "good" : t.good === false ? "bad" : "neutral";
  const lineTone = t.good === true ? "up" : t.good === false ? "down" : "neutral";
  const chip = <ChangeChip text={t.deltaLabel} direction={direction} tone={chipTone} />;
  const label = <h4 className="truncate text-sm font-medium text-muted-foreground">{m.label}</h4>;
  const foot = (
    <div className="mt-auto flex flex-col gap-2 pt-1">
      <Unusual m={m} t={t} />
      {m.note ? <p className="line-clamp-2 text-[13px] text-muted-foreground">{m.note}</p> : null}
      <span className="text-xs text-muted-foreground">
        as of <Time iso={m.as_of} />
      </span>
    </div>
  );

  if (kind === "ring") {
    const share = Math.max(0, Math.min(1, t.value / 100));
    return (
      <article className={cn(CARD, "flex flex-col gap-3 p-5", r.className)} style={r.style}>
        {label}
        <div className="flex items-center gap-4">
          <RingGauge value={share} size={88} stroke={8} tone={t.good === false ? "warn" : "neutral"} label={`${m.label}: ${t.valueLabel}`}>
            <span className="text-[15px] font-semibold tabular-nums">
              <AnimatedNumber value={t.value} format="metric" unit={m.unit ?? undefined} />
            </span>
          </RingGauge>
          <div className="flex min-w-0 flex-col items-start gap-1.5">
            {chip}
            {t.usual != null ? <span className="text-[13px] text-muted-foreground">usually {formatMetricValue(t.usual, m.unit)}</span> : null}
          </div>
        </div>
        {t.points.length > 1 ? <Sparkline points={t.points} tone={lineTone} className="h-9" label={`${m.label}, the last ${t.points.length} readings`} /> : null}
        {foot}
      </article>
    );
  }

  const big = kind === "money";
  return (
    <article className={cn(CARD, "flex flex-col gap-3 p-5", big && "sm:col-span-2", r.className)} style={r.style}>
      <div className="flex items-start justify-between gap-3">
        {label}
        {chip}
      </div>
      <div className={cn("font-heading leading-none font-semibold tracking-tight", big ? "text-[40px] max-sm:text-[34px]" : "text-[30px]")}>
        <AnimatedNumber value={t.value} format="metric" unit={m.unit ?? undefined} />
      </div>
      {t.points.length > 1 ? (
        <Sparkline points={t.points} tone={lineTone} className={big ? "h-20" : "h-12"} label={`${m.label}, the last ${t.points.length} readings`} />
      ) : (
        <div className={big ? "h-20" : "h-12"} />
      )}
      {foot}
    </article>
  );
}

// "Unusually low · usually 241 ms" when the latest is far off its history
// (the same robust z the Today insights use), in green or red by whether
// that's good news, with a question for the assistant.
function Unusual({ m, t }: { m: MetricRow; t: TodayMetric }) {
  if (t.z == null || Math.abs(t.z) < ANOMALY_Z || t.usual == null) return null;
  const high = t.z > 0;
  const good = high === (goodDirection(m.unit, m.key) === "up");
  return (
    <div className="flex flex-wrap items-center gap-2">
      <span className={cn("inline-flex items-center gap-1 text-[13px] font-medium", good ? "text-success" : "text-destructive")}>
        <SparklesIcon className="size-3.5" aria-hidden="true" />
        Unusually {high ? "high" : "low"} · usually {formatMetricValue(t.usual, m.unit)}
      </span>
      <AskLink question={`Why is ${m.label} ${high ? "so high" : "so low"} right now?`} label="Ask why" />
    </div>
  );
}
