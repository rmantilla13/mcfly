import { CircleAlertIcon } from "lucide-react";
import { RingGauge } from "@/components/charts/RingGauge";
import { StatusDot } from "@/components/charts/StatusDot";
import type { TodayProject } from "@/lib/today";
import { Tile } from "./Tile";

// The blocked project: the one thing only you can unstick. Its progress is
// a ring, its next step under its name, and its dot breathes (slowly) as
// the display's blocked tile does: the page's one real alert.

export function NeedsYouCard({ blocked, index, className }: { blocked: TodayProject[]; index: number; className?: string }) {
  const p = blocked[0];
  const more = blocked.length - 1;
  const pct = p.progress != null ? Math.round(p.progress) : null;
  return (
    <Tile href={`/feed/projects/${p.id}`} index={index} className={className} style={{ backgroundColor: "color-mix(in oklab, var(--destructive) 7%, var(--card))" }}>
      <div className="flex h-full flex-col gap-4 p-5">
        <div className="flex min-h-7 items-center gap-2.5">
          <StatusDot state="down" className="size-2" />
          <h2 className="text-xs font-bold tracking-[0.12em] text-destructive uppercase">Needs you</h2>
          {more > 0 ? <span className="ml-auto text-xs font-medium text-muted-foreground">+{more} more blocked</span> : null}
        </div>
        <div className="mt-auto flex items-center gap-4">
          {pct != null ? (
            <RingGauge value={pct / 100} size={64} stroke={6} tone="down" label={`${p.name}: ${pct}% done`}>
              <span className="text-[15px] font-semibold tabular-nums">
                {pct}
                <span className="text-[10px] text-muted-foreground">%</span>
              </span>
            </RingGauge>
          ) : (
            <span className="grid size-16 shrink-0 place-items-center rounded-full bg-destructive/12 text-destructive" aria-hidden="true">
              <CircleAlertIcon className="size-6" />
            </span>
          )}
          <span className="min-w-0">
            <span className="block truncate text-lg leading-snug font-semibold">{p.name} is blocked</span>
            {p.next ? <span className="mt-0.5 line-clamp-2 block text-sm text-muted-foreground">{p.next}</span> : null}
          </span>
        </div>
      </div>
    </Tile>
  );
}
