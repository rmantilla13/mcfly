import { cn } from "cn";
import { ZapIcon } from "lucide-react";
import { AnimatedNumber } from "@/components/AnimatedNumber";
import { Time } from "@/components/bits";
import { BarStrip } from "@/components/charts";
import { CARD } from "@/components/feed/styles";
import { hourSpanLabel, pushBars } from "@/lib/feed-layout";
import { formatNumber, plural } from "@/lib/format";
import type { IngestEntry } from "@/lib/types";

// The Overview's hero: how many pushes landed in the last day, counting up,
// over a bar for each hour stacked by feed, with a red tick over any hour
// that had a push refused. The number is admin_overview's; the bars are the
// log's rows (the newest 1000), so on a very busy day they can fall short
// of it, and the card says so.

const LOG_CAP = 1000;

export function PushesCard({
  total,
  refused,
  lastPushAt,
  entries,
  now,
  timeZone,
  className,
}: {
  total: number;
  refused: number;
  lastPushAt: string | null;
  entries: IngestEntry[];
  now: number;
  timeZone: string;
  className?: string;
}) {
  const data = pushBars(entries, now);
  const counts = data.series.map((_, s) => data.bars.reduce((sum, b) => sum + b.values[s], 0));
  const peak = data.bars.reduce((best, b, i) => (b.values.reduce((a, v) => a + v, 0) > data.bars[best].values.reduce((a, v) => a + v, 0) ? i : best), 0);
  const peakTotal = data.bars[peak]?.values.reduce((a, v) => a + v, 0) ?? 0;
  return (
    <section className={cn(CARD, "flex flex-col gap-5 p-6 max-sm:p-5", className)} aria-label="Pushes, last 24 hours">
      <div className="flex flex-wrap items-end justify-between gap-x-6 gap-y-3">
        <div>
          <h2 className="flex items-center gap-2 text-sm font-medium text-muted-foreground">
            <span className="grid size-7 place-items-center rounded-lg bg-accent text-accent-foreground" aria-hidden="true">
              <ZapIcon className="size-4" />
            </span>
            Pushes, last 24h
          </h2>
          <div className="mt-3 font-heading text-[52px] leading-none font-semibold tracking-tight max-sm:text-[44px]">
            <AnimatedNumber value={total} format="int" />
          </div>
          <p className="mt-2.5 text-[13px] text-muted-foreground">
            {lastPushAt ? (
              <>
                Last one <Time iso={lastPushAt} />
              </>
            ) : (
              "Nothing yet"
            )}
            {refused ? (
              <>
                {" · "}
                <span className="font-medium text-destructive">{plural(refused, "push", "pushes")} refused</span>
              </>
            ) : null}
          </p>
        </div>
        {peakTotal > 0 ? (
          <p className="text-right text-[13px] text-muted-foreground max-sm:text-left">
            Busiest hour
            <span className="block font-medium text-foreground">
              {hourSpanLabel(data.bars[peak].end, timeZone)} · {formatNumber(peakTotal)}
            </span>
          </p>
        ) : null}
      </div>
      <div className="flex flex-col gap-2">
        <BarStrip
          bars={data.bars.map((b) => ({ label: hourSpanLabel(b.end, timeZone), values: b.values, alert: b.alert }))}
          series={data.series.map((s) => ({ label: s.label }))}
          height={112}
          label="Pushes in the last 24 hours, by hour"
          alertLabel="refused"
          format="int"
        />
        <div className="flex justify-between text-xs text-muted-foreground" aria-hidden="true">
          <span>24 h ago</span>
          <span>12 h ago</span>
          <span>now</span>
        </div>
      </div>
      {data.series.length ? (
        <ul className="flex flex-wrap gap-x-4 gap-y-1.5 text-[13px] text-muted-foreground">
          {data.series.map((s, i) => (
            <li key={s.feed} className="inline-flex items-center gap-1.5">
              {/* BarStrip's own colours: --chart-1…5 in series order. */}
              <span className="size-2.5 rounded-[3px]" style={{ background: `var(--chart-${(i % 5) + 1})` }} aria-hidden="true" />
              {s.label}
              <span className="font-medium text-foreground tabular-nums">{formatNumber(counts[i])}</span>
            </li>
          ))}
          {data.refused ? (
            <li className="inline-flex items-center gap-1.5">
              <span className="h-[3px] w-2.5 rounded-full bg-destructive" aria-hidden="true" />
              Refused
              <span className="font-medium text-foreground tabular-nums">{formatNumber(data.refused)}</span>
            </li>
          ) : null}
        </ul>
      ) : null}
      {entries.length >= LOG_CAP ? <p className="text-xs text-muted-foreground">The bars show the newest {formatNumber(LOG_CAP)} entries in the log.</p> : null}
    </section>
  );
}
