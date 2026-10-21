import { cn } from "cn";
import { ExternalLinkIcon, FolderKanbanIcon } from "lucide-react";
import Link from "next/link";
import type { CSSProperties } from "react";
import { EmptyState, ProjectStatusBadge, Time } from "@/components/bits";
import { StatusDot, type StatusState } from "@/components/charts";
import { StageBar } from "@/components/StageTrack";
import { CARD, rise, STRETCH } from "@/components/feed/styles";
import { Progress } from "@/components/ui/progress";
import { projectLanes, stageTrack, timeInStage } from "@/lib/feed-layout";
import { cssColor, plural } from "@/lib/format";
import type { ProjectRow, ProjectStatus } from "@/lib/types";

// The Projects tab as a list: where everything stands at the top (a bar
// split by status, a count for each that jumps to its group), then a group
// per status, the one that needs you first, a row per project. Each row is
// the project (its colour down the left, what it is, whose it is), the
// stage it is in as a bar of stages with how long it has been there, what's
// next, and its status and newest update. A project without stages shows
// its progress instead, or nothing. Rows open the project's page.

const DOT: Record<ProjectStatus, StatusState> = { blocked: "down", active: "ok", paused: "warn", done: "unknown" };
const SHARE: Record<ProjectStatus, string> = {
  blocked: "bg-destructive",
  active: "bg-success",
  paused: "bg-warning",
  done: "bg-muted-foreground/35",
};

export function ProjectsList({ projects, now }: { projects: ProjectRow[]; now: number }) {
  if (projects.length === 0) {
    return (
      <EmptyState title="No projects" icon={<FolderKanbanIcon />}>
        Projects an agent pushes (POST /ingest/projects) are listed here by status, each with the stage it is in.
      </EmptyState>
    );
  }
  const lanes = projectLanes(projects);
  let index = 0;
  return (
    <div className="flex flex-col gap-6">
      <StatusOverview lanes={lanes} total={projects.length} />
      {lanes
        .filter((lane) => lane.projects.length > 0)
        .map((lane) => (
          <section key={lane.status} id={`projects-${lane.status}`} aria-labelledby={`projects-${lane.status}-title`} className="scroll-mt-24">
            <h3 id={`projects-${lane.status}-title`} className="mb-2.5 flex items-center gap-2 px-1 text-sm font-semibold">
              <StatusDot state={DOT[lane.status]} pulse={false} />
              {lane.label}
              <span className="rounded-full bg-foreground/8 px-2 text-xs font-normal text-muted-foreground tabular-nums">{lane.projects.length}</span>
            </h3>
            <ol className={cn(CARD, "divide-y divide-foreground/8 overflow-hidden", lane.status === "blocked" && "feed-alert")}>
              {lane.projects.map((p) => (
                <ProjectRowItem key={p.id} p={p} index={index++} now={now} />
              ))}
            </ol>
          </section>
        ))}
    </div>
  );
}

// One bar for every project, a share per status, and the four counts under
// it as links to their groups.
function StatusOverview({ lanes, total }: { lanes: ReturnType<typeof projectLanes<ProjectRow>>; total: number }) {
  const open = total - (lanes.find((l) => l.status === "done")?.projects.length ?? 0);
  return (
    <section className={cn(CARD, "flex flex-col gap-4 p-5", rise(0).className)} style={rise(0).style} aria-labelledby="projects-status-title">
      <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
        <h3 id="projects-status-title" className="font-heading text-base font-semibold">
          Status
        </h3>
        <span className="text-[13px] text-muted-foreground">
          {plural(total, "project")} · {open} open
        </span>
      </div>
      <div className="flex h-3 gap-[3px] overflow-hidden rounded-full" role="img" aria-label={lanes.map((l) => `${l.projects.length} ${l.label.toLowerCase()}`).join(", ")}>
        {lanes
          .filter((l) => l.projects.length > 0)
          .map((l, i) => (
            <span
              key={l.status}
              className={cn("feed-grow-x h-full origin-left first:rounded-l-full last:rounded-r-full", SHARE[l.status])}
              style={{ flexGrow: l.projects.length, flexBasis: 0, "--i": i } as CSSProperties}
            />
          ))}
      </div>
      <ul className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        {lanes.map((l) => {
          const n = l.projects.length;
          const inner = (
            <>
              <span className="flex items-center gap-2 text-[13px] text-muted-foreground">
                <StatusDot state={DOT[l.status]} pulse={l.status === "blocked" && n > 0 ? undefined : false} />
                {l.label}
              </span>
              <span className={cn("font-heading text-2xl leading-none font-semibold tabular-nums", n === 0 && "text-muted-foreground/60")}>{n}</span>
            </>
          );
          const box = "flex flex-col gap-2 rounded-2xl px-3.5 py-3 ring-1 ring-foreground/8";
          return (
            <li key={l.status}>
              {n > 0 ? (
                <a
                  href={`#projects-${l.status}`}
                  className={cn(
                    box,
                    "text-foreground no-underline transition-colors outline-none hover:bg-accent focus-visible:ring-2 focus-visible:ring-ring",
                    l.status === "blocked" && "bg-destructive/[0.05] dark:bg-destructive/[0.08]",
                  )}
                >
                  {inner}
                </a>
              ) : (
                <div className={box}>{inner}</div>
              )}
            </li>
          );
        })}
      </ul>
    </section>
  );
}

function ProjectRowItem({ p, index, now }: { p: ProjectRow; index: number; now: number }) {
  const color = cssColor(p.color) ?? cssColor(p.agent_color);
  const track = stageTrack(p);
  const done = p.status === "done";
  const r = rise(index + 1);
  // What's next while it's open; what happened last once it's done (or when
  // nobody said what's next).
  const next = !done && p.next_step ? p.next_step : null;
  return (
    <li
      className={cn(
        "relative grid grid-cols-1 gap-3 py-4 pr-4 pl-5 transition-colors hover:bg-foreground/[0.025] has-[a:focus-visible]:bg-foreground/[0.025] md:grid-cols-[minmax(0,1.15fr)_minmax(0,1.35fr)_minmax(0,1.2fr)_9rem] md:items-center md:gap-6 md:pr-5",
        r.className,
      )}
      style={r.style}
    >
      <span aria-hidden="true" className="absolute inset-y-0 left-0 w-1.5 bg-primary" style={color ? { background: color } : undefined} />

      <div className="flex min-w-0 items-start justify-between gap-3">
        <div className="min-w-0">
          <Link href={`/feed/projects/${p.id}`} className={cn(STRETCH, "block truncate font-semibold text-foreground no-underline", done && "text-muted-foreground")}>
            {p.name}
          </Link>
          <div className="mt-0.5 flex min-w-0 items-center gap-1.5 text-xs text-muted-foreground">
            <span>{p.kind}</span>
            <span aria-hidden="true">·</span>
            <span className="truncate">{p.agent_name}</span>
            {p.link ? (
              <a
                href={p.link}
                target="_blank"
                rel="noopener noreferrer"
                className="relative z-10 -m-1 shrink-0 rounded p-1 hover:text-foreground"
                aria-label={`Open ${p.name}'s link`}
              >
                <ExternalLinkIcon className="size-3.5" />
              </a>
            ) : null}
          </div>
        </div>
        {/* On a phone the status rides with the name; wider, it has a column. */}
        <span className="shrink-0 md:hidden">
          <ProjectStatusBadge status={p.status} />
        </span>
      </div>

      <div className="min-w-0">
        {track ? (
          <StageBar track={track} color={color} since={track.current && !done ? timeInStage(p.stage_since, now) : undefined} />
        ) : p.progress != null ? (
          <div className="flex flex-col gap-1.5">
            <div className="flex items-baseline justify-between gap-3 text-[13px] leading-tight">
              <span className="text-muted-foreground">No stages</span>
              <span className="text-xs text-muted-foreground tabular-nums">{p.progress}% done</span>
            </div>
            <Progress value={p.progress} aria-label={`${p.progress}% done`} className="h-1.5" />
          </div>
        ) : (
          <span className="text-[13px] text-muted-foreground">No stages</span>
        )}
      </div>

      <div className="min-w-0 text-[13px] leading-snug">
        {next ? (
          <p className="line-clamp-2">
            <span className="font-medium">Next:</span> {next}
          </p>
        ) : p.last_update ? (
          <p className="line-clamp-2 text-muted-foreground" title={p.last_update}>
            {p.last_update}
          </p>
        ) : (
          <p className="text-muted-foreground">{p.summary ? p.summary : "Nothing said yet."}</p>
        )}
      </div>

      <div className="flex items-center gap-3 text-xs text-muted-foreground md:flex-col md:items-end md:gap-1.5">
        <span className="max-md:hidden">
          <ProjectStatusBadge status={p.status} />
        </span>
        <span>
          updated <Time iso={p.last_update_at ?? p.updated_at} />
        </span>
      </div>
    </li>
  );
}
