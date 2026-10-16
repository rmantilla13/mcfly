import { cn } from "cn";
import { GaugeIcon } from "lucide-react";
import Link from "next/link";
import { AnimatedNumber } from "@/components/AnimatedNumber";
import { Sparkline } from "@/components/charts/Sparkline";
import type { TodayMetric } from "@/lib/today";
import { Tile, TileHead } from "./Tile";

// The agents' numbers, one row each: the value (counting to a new one), its
// change coloured by whether that is good news for it (a falling latency
// is), and its recent line in the same colour. One far off its usual says
// so. Unusual ones first, four at most; the Metrics tab has the rest.

const SHOWN = 4;

// `alone`: no markets beside it, so it has the whole row.
export function MetricTiles({ metrics, alone = false, index, className }: { metrics: TodayMetric[]; alone?: boolean; index: number; className?: string }) {
  const unusual = (m: TodayMetric) => m.z != null && Math.abs(m.z) >= 3;
  const shown = [...metrics].sort((a, b) => Number(unusual(b)) - Number(unusual(a))).slice(0, SHOWN);
  return (
    <Tile index={index} label="Metrics" className={cn("gap-3 p-5", className)}>
      <TileHead
        icon={<GaugeIcon />}
        action={
          metrics.length > SHOWN ? (
            <Link href="/feed?tab=metrics" className="text-[13px] font-medium text-muted-foreground no-underline hover:text-foreground">
              All {metrics.length}
            </Link>
          ) : null
        }
      >
        Metrics
      </TileHead>
      {/* One column in the narrow tile beside Markets; two when it has a row to itself. */}
      <ul className={cn("grid gap-x-6 gap-y-1", alone ? "sm:grid-cols-2 xl:grid-cols-4" : "sm:max-xl:grid-cols-2")}>
        {shown.map((m) => {
          const tone = m.good == null ? "neutral" : m.good ? "up" : "down";
          return (
            <li key={m.key}>
              <Link
                href="/feed?tab=metrics"
                className="-mx-2 flex items-center gap-3 rounded-2xl px-2 py-2 text-foreground no-underline transition-colors outline-none hover:bg-muted focus-visible:ring-2 focus-visible:ring-ring"
              >
                <span className="min-w-0 flex-1">
                  <span className="flex items-center gap-1.5 text-[13px] text-muted-foreground">
                    <span className="truncate">{m.label}</span>
                    {unusual(m) ? (
                      <span className="shrink-0 rounded-full bg-warning/12 px-1.5 text-[11px] font-semibold text-warning">Unusual</span>
                    ) : null}
                  </span>
                  <span className="block text-lg leading-tight font-semibold tracking-tight tabular-nums">
                    <AnimatedNumber value={m.value} format="metric" unit={m.unit ?? undefined} />
                  </span>
                </span>
                {m.points.length > 1 ? (
                  <Sparkline points={m.points} tone={tone} dot={false} className="h-8 w-16 shrink-0" />
                ) : null}
                {m.deltaLabel ? (
                  <span
                    className={cn(
                      "w-[4.5rem] shrink-0 text-right text-[13px] font-semibold tabular-nums",
                      tone === "up" && "text-success",
                      tone === "down" && "text-destructive",
                      tone === "neutral" && "text-muted-foreground",
                    )}
                  >
                    {/* "+$476.00 (+12.5%)" is too long for the row; the percent says it. */}
                    {/\(([^)]+)\)$/.exec(m.deltaLabel)?.[1] ?? m.deltaLabel}
                  </span>
                ) : null}
              </Link>
            </li>
          );
        })}
      </ul>
    </Tile>
  );
}
