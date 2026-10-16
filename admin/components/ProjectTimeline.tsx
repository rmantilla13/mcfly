import { cn } from "cn";
import {
  CircleAlertIcon,
  CircleCheckIcon,
  ExternalLinkIcon,
  FlagIcon,
  GitCommitHorizontalIcon,
  GitPullRequestIcon,
  type LucideIcon,
  RocketIcon,
  StickyNoteIcon,
} from "lucide-react";
import type { CSSProperties } from "react";
import { Time } from "@/components/bits";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { dayKey } from "@/lib/events";
import { activityByDay, groupByDay } from "@/lib/feed-layout";
import { formatDateTime, plural } from "@/lib/format";
import type { ProjectUpdate, ProjectUpdateKind } from "@/lib/types";

// A project's history as a timeline: a rail down the left with a node per
// update, the kind as its icon and colour, a line for each day. Newest at
// the top. And its last month as a strip of days, darker the busier.

const KIND: Record<ProjectUpdateKind, { label: string; Icon: LucideIcon; node: string; icon: string }> = {
  commit: { label: "Commit", Icon: GitCommitHorizontalIcon, node: "bg-chart-1/14", icon: "text-chart-1" },
  pr: { label: "Pull request", Icon: GitPullRequestIcon, node: "bg-chart-5/14", icon: "text-chart-5" },
  ci: { label: "CI", Icon: CircleCheckIcon, node: "bg-success/14", icon: "text-success" },
  deploy: { label: "Deploy", Icon: RocketIcon, node: "bg-chart-2/14", icon: "text-chart-2" },
  alert: { label: "Alert", Icon: CircleAlertIcon, node: "bg-destructive/12", icon: "text-destructive" },
  done: { label: "Done", Icon: FlagIcon, node: "bg-success", icon: "text-success-foreground" },
  note: { label: "Note", Icon: StickyNoteIcon, node: "bg-muted", icon: "text-muted-foreground" },
};

const CLOCKS = new Map<string, Intl.DateTimeFormat>();
function clock(iso: string, timeZone: string): string {
  let f = CLOCKS.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric", minute: "2-digit" });
    CLOCKS.set(timeZone, f);
  }
  const t = Date.parse(iso);
  return Number.isFinite(t) ? f.format(t) : "";
}

export function ProjectTimeline({ updates, timeZone, now }: { updates: ProjectUpdate[]; timeZone: string; now: number }) {
  const days = groupByDay(updates, (u) => u.happened_at, timeZone, new Date(now));
  // "2 hr. ago" only under Today: further back the day's line says when, and
  // a relative "yesterday" (a day's span) can disagree with the calendar's.
  const today = dayKey(new Date(now), timeZone);
  let index = 0;
  return (
    <div className="relative">
      {/* The rail, behind the nodes. */}
      <span aria-hidden="true" className="absolute top-3 bottom-3 left-[17px] w-0.5 rounded-full bg-foreground/8" />
      <ol className="relative flex flex-col gap-1">
        {days.map((day) => (
          <li key={day.day} className="flex flex-col">
            <div className="flex items-center gap-3 py-2 pl-[7px]">
              <span aria-hidden="true" className="size-[22px] shrink-0 rounded-full bg-card p-[7px]">
                <span className="block size-2 rounded-full bg-foreground/25" />
              </span>
              <span className="text-xs font-semibold tracking-wider text-muted-foreground uppercase">{day.label}</span>
            </div>
            <ol className="flex flex-col">
              {day.items.map((u) => {
                const kind = KIND[u.kind] ?? KIND.note;
                const i = Math.min(index++, 8);
                return (
                  <li key={u.id} className="feed-rise grid grid-cols-[36px_minmax(0,1fr)] gap-3 py-2" style={{ "--i": i } as CSSProperties}>
                    {/* An opaque disc under the tint, so the rail stops at the node. */}
                    <span className="relative grid size-9 place-items-center rounded-full bg-card ring-4 ring-card" aria-hidden="true">
                      <span className={cn("absolute inset-0 rounded-full", kind.node)} />
                      <kind.Icon className={cn("relative size-4", kind.icon)} />
                    </span>
                    <div className="min-w-0 pt-0.5">
                      <div className="text-[15px] leading-snug text-pretty">
                        {u.url ? (
                          <a href={u.url} target="_blank" rel="noopener noreferrer" className="hover:underline">
                            {u.text}
                            <ExternalLinkIcon className="ml-1 inline size-3 align-[-1px] text-muted-foreground" aria-hidden="true" />
                          </a>
                        ) : (
                          u.text
                        )}
                      </div>
                      <div className="mt-0.5 flex flex-wrap gap-x-1.5 text-xs text-muted-foreground">
                        <span>{kind.label}</span>
                        <span aria-hidden="true">·</span>
                        <time dateTime={u.happened_at} title={formatDateTime(u.happened_at)}>
                          {clock(u.happened_at, timeZone)}
                        </time>
                        {day.day === today ? (
                          <>
                            <span aria-hidden="true">·</span>
                            <Time iso={u.happened_at} />
                          </>
                        ) : null}
                      </div>
                    </div>
                  </li>
                );
              })}
            </ol>
          </li>
        ))}
      </ol>
    </div>
  );
}

const DAY_NAME = new Intl.DateTimeFormat("en-US", { weekday: "short", month: "short", day: "numeric", timeZone: "UTC" });

// The last `days` days as cells, a day each, in the project's colour (or the
// brand blue): empty days faint, busy ones full. Each tells its count when
// pointed at; a screen reader gets the busy days as a list instead (the
// strip is one image to it). The cells take no focus: thirty tab stops for
// what the timeline below already says, day by day.
export function ActivityStrip({ updates, timeZone, color, days = 30, now }: { updates: ProjectUpdate[]; timeZone: string; color: string | null; days?: number; now: number }) {
  const cells = activityByDay(
    updates.map((u) => u.happened_at),
    days,
    now,
    timeZone,
  );
  const most = Math.max(1, ...cells.map((c) => c.count));
  const total = cells.reduce((sum, c) => sum + c.count, 0);
  const label = (day: string) => DAY_NAME.format(Date.parse(`${day}T12:00:00Z`));
  return (
    <div className="flex flex-col gap-2">
      <div className="flex h-10 items-stretch gap-[3px]" role="img" aria-label={`${plural(total, "update")} in the last ${days} days`}>
        {cells.map((c, i) => (
          <Tooltip key={c.day}>
            <TooltipTrigger asChild>
              <span
                className={cn("feed-grow min-w-0 flex-1 rounded-[4px]", c.count ? (color ? "" : "bg-primary") : "bg-foreground/8")}
                style={{
                  ...(c.count && color ? { background: color } : {}),
                  opacity: c.count ? 0.35 + (0.65 * c.count) / most : undefined,
                  "--i": i,
                } as CSSProperties}
              />
            </TooltipTrigger>
            <TooltipContent side="top" sideOffset={6} className="rounded-lg px-2.5 py-1.5">
              <span className="text-background/70">{label(c.day)}</span>
              <span className="font-semibold tabular-nums">{c.count ? plural(c.count, "update") : "Nothing"}</span>
            </TooltipContent>
          </Tooltip>
        ))}
      </div>
      {total ? (
        <ul className="sr-only">
          {cells
            .filter((c) => c.count)
            .map((c) => (
              <li key={c.day}>
                {label(c.day)}: {plural(c.count, "update")}
              </li>
            ))}
        </ul>
      ) : null}
      <div className="flex justify-between text-xs text-muted-foreground" aria-hidden="true">
        <span>{label(cells[0].day)}</span>
        <span>Today</span>
      </div>
    </div>
  );
}
