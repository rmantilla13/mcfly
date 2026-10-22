import { cn } from "cn";
import { FlameIcon } from "lucide-react";
import { type DayLoad, heatColor, loadKind } from "@/lib/day-load";
import { cssColor } from "@/lib/format";
import type { EventRow } from "@/lib/types";

// One day's hours as a slim strip, as the app's day tile and the display's
// day view draw them: each timed event a bar where it falls (8 AM to 8 PM,
// or wider for an earlier or later one), amber when it runs straight into
// the next, a red mark where two run at once, and under it a band that
// warms with how booked the hours around each moment are. Then a line: the
// busiest stretch, the conflicts and the back-to-back runs. Server-drawn,
// no client JS; the strip is one image to a screen reader, and the event
// rows below say the same in words.

const HOUR = 3_600_000;
// The app's amber (Theme.warning), the same by day and night; words use the
// console's --warning, which darkens by day so it reads.
const AMBER = "#F2A93B";

const HOURS = new Map<string, Intl.DateTimeFormat>();
function hourFormat(timeZone: string, minutes: boolean) {
  const key = `${timeZone}|${minutes}`;
  let f = HOURS.get(key);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric", ...(minutes ? { minute: "2-digit" } : {}) });
    HOURS.set(key, f);
  }
  return f;
}
// "10 AM", or "10:30 AM" off the hour.
function clock(ms: number, timeZone: string): string {
  return hourFormat(timeZone, new Date(ms).getUTCMinutes() !== 0).format(ms);
}

export function DayLoadStrip({ events, load, timeZone }: { events: EventRow[]; load: DayLoad; timeZone: string }) {
  const timed = events.filter((e) => !e.all_day);
  if (timed.length === 0) return null;
  const hourOf = (ms: number) => Math.max(0, Math.min(24, (ms - load.dayStart) / HOUR));
  const first = Math.min(8, ...timed.map((e) => Math.floor(hourOf(Date.parse(e.starts_at)))));
  const last = Math.max(20, ...timed.map((e) => Math.ceil(hourOf(Date.parse(e.ends_at)))));
  const span = Math.max(1, last - first);
  const pct = (ms: number) => `${((hourOf(ms) - first) / span) * 100}%`;
  const width = (from: number, to: number) => `max(6px, ${((hourOf(to) - hourOf(from)) / span) * 100}%)`;
  // The heat as gradient stops, a quarter hour each across the strip's hours.
  const stops: string[] = [];
  for (let i = first * 4; i < Math.min(load.heat.length, last * 4); i++) {
    const at = (((i + 0.5) / 4 - first) / span) * 100;
    stops.push(`${heatColor(load.heat[i]) ?? "transparent"} ${at.toFixed(2)}%`);
  }
  const label = (h: number) => hourFormat(timeZone, false).format(load.dayStart + h * HOUR);
  const conflicts = load.conflicts.length;
  const links = load.backToBackCount;

  return (
    <div className="flex flex-col gap-1.5 pt-1 pb-2">
      <div className="relative h-2.5 rounded-full bg-foreground/8" role="img" aria-label={summaryText(load, timeZone)}>
        {timed.map((e) => {
          const from = Date.parse(e.starts_at);
          const to = Date.parse(e.ends_at);
          const fill = loadKind(load, e.id) === "backToBack" ? AMBER : cssColor(e.color);
          return (
            <span
              key={e.id}
              className={cn("absolute inset-y-0 rounded-full", !fill && "bg-primary")}
              style={{ left: pct(from), width: width(from, to), ...(fill ? { background: fill } : {}) }}
            />
          );
        })}
        {load.conflicts.map((s) => (
          <span
            key={s.start}
            className="absolute -inset-y-0.5 rounded-full bg-destructive ring-1 ring-background/50"
            style={{ left: pct(s.start), width: width(s.start, s.end) }}
          />
        ))}
      </div>
      {stops.length > 1 ? <div className="h-1 rounded-full" style={{ background: `linear-gradient(to right, ${stops.join(", ")})` }} aria-hidden="true" /> : null}
      <div className="flex justify-between text-[11px] text-muted-foreground tabular-nums" aria-hidden="true">
        <span>{label(first)}</span>
        <span>{label(Math.floor((first + last) / 2))}</span>
        <span>{label(last)}</span>
      </div>
      {load.busiest || conflicts || links ? (
        <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs font-medium" aria-hidden="true">
          {load.busiest ? (
            <span className="inline-flex items-center gap-1.5">
              <FlameIcon className="size-3.5" style={{ color: AMBER }} />
              Busiest {clock(load.busiest.start, timeZone)} – {clock(load.busiest.end, timeZone)}
            </span>
          ) : null}
          {conflicts ? (
            <span className="inline-flex items-center gap-1.5">
              <span className="size-2 rounded-full bg-destructive" />
              {conflicts === 1 ? "1 conflict" : `${conflicts} conflicts`}
            </span>
          ) : null}
          {links ? (
            <span className="inline-flex items-center gap-1.5">
              <span className="size-2 rounded-full" style={{ background: AMBER }} />
              {links} back to back
            </span>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}

// The strip in words, for a screen reader.
function summaryText(load: DayLoad, timeZone: string): string {
  const parts: string[] = [];
  if (load.busiest) parts.push(`busiest ${clock(load.busiest.start, timeZone)} to ${clock(load.busiest.end, timeZone)}`);
  if (load.conflicts.length) parts.push(load.conflicts.length === 1 ? "1 conflict" : `${load.conflicts.length} conflicts`);
  if (load.backToBackCount) parts.push(`${load.backToBackCount} back to back`);
  return parts.length ? `The day's hours: ${parts.join(", ")}` : "The day's hours";
}
