import type { CSSProperties } from "react";
import { MeshGradient } from "@/components/MeshGradient";
import { RingGauge } from "@/components/charts/RingGauge";
import { dayKey, dayLabel } from "@/lib/events";
import { cssColor } from "@/lib/format";
import { countdown, formatClock, untilLabel, type TodayEvent } from "@/lib/today";
import { Tile } from "./Tile";

// What's on now or next, on the display's moving gradient in the event's
// colour (MeshGradient, as the display's GradientTile): pastel by day,
// deep at night, so the ink is the theme's own. Within the hour a ring
// fills as it nears; once it starts, the ring is how far through it is.
// One of the page's two WebGL tiles. The tint under it is what shows
// without WebGL.

export function UpNextCard({ event, now, timeZone, index, className }: { event: TodayEvent; now: number; timeZone: string; index: number; className?: string }) {
  const color = cssColor(event.color) ?? "#5B7CF5";
  const start = Date.parse(event.starts_at);
  const end = Date.parse(event.ends_at);
  const c = countdown(start, end, now);
  const day = dayKey(event.starts_at, timeZone);
  const today = day === dayKey(new Date(now), timeZone);
  const kicker =
    c.mode === "now"
      ? `Now · ends ${untilLabel(end, now)}`
      : today
        ? `Up next · ${untilLabel(start, now)}`
        : `${dayLabel(day, timeZone, new Date(now))} · ${formatClock(start, timeZone)}`;
  const where = event.location || event.calendar;

  return (
    <Tile
      href="/feed?tab=calendar"
      index={index}
      className={className}
      style={{ backgroundColor: `color-mix(in oklab, ${color} 22%, var(--card))` } as CSSProperties}
    >
      <div className="absolute inset-0 overflow-hidden rounded-[inherit]" aria-hidden="true">
        <MeshGradient className="absolute inset-0" baseColor={color} rings={1} seed={2} maxFps={15} resolution={0.75} />
      </div>
      <div className="relative flex h-full min-h-[184px] items-center gap-5 p-6 max-sm:p-5">
        <div className="flex min-w-0 flex-1 flex-col gap-1 self-stretch">
          <span className="text-xs font-bold tracking-[0.12em] uppercase opacity-75" suppressHydrationWarning>
            {kicker}
          </span>
          <span className="mt-auto line-clamp-2 text-[28px] leading-tight font-semibold tracking-[-0.01em] max-sm:text-2xl">{event.title}</span>
          <span className="truncate text-[15px] opacity-80">
            {[`${formatClock(start, timeZone)} – ${formatClock(end, timeZone)}`, where].filter(Boolean).join(" · ")}
          </span>
        </div>
        {c.mode !== "later" ? (
          <div className="shrink-0 rounded-full bg-card/45 p-1.5 shadow-sm backdrop-blur-md">
            <RingGauge
              value={c.value}
              size={88}
              stroke={7}
              color={color}
              label={c.mode === "now" ? `${c.minutes} minutes left` : `Starts in ${c.minutes} minutes`}
            >
              <span className="text-[26px] font-semibold tabular-nums" suppressHydrationWarning>
                {c.minutes}
              </span>
              <span className="mt-0.5 text-[11px] font-semibold tracking-[0.08em] text-muted-foreground uppercase">
                {c.mode === "now" ? "min left" : "min"}
              </span>
            </RingGauge>
          </div>
        ) : null}
      </div>
    </Tile>
  );
}
