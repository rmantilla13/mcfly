import { cn } from "cn";
import { ExternalLinkIcon, FolderKanbanIcon } from "lucide-react";
import Link from "next/link";
import { EmptyState, Time } from "@/components/bits";
import { RingGauge, type StatusState, StatusDot } from "@/components/charts";
import { AskLink } from "@/components/feed/bits";
import { CARD, LIFT, rise, STRETCH } from "@/components/feed/styles";
import { projectLanes } from "@/lib/feed-layout";
import { cssColor, plural } from "@/lib/format";
import type { ProjectRow, ProjectStatus } from "@/lib/types";

// The Projects tab as a board: a lane per status, the one that needs you
// first. Each card wears its project's colour (or its agent's) down the left
// edge and its progress as a ring, with the next step and the newest update.
// The blocked lane's border breathes, slowly, while anything is in it. Cards
// open the project's history.

const LANE_DOT: Record<ProjectStatus, StatusState> = { blocked: "down", active: "ok", paused: "warn", done: "unknown" };
const EMPTY: Record<ProjectStatus, string> = {
  blocked: "Nothing blocked.",
  active: "Nothing in progress.",
  paused: "Nothing paused.",
  done: "Nothing finished yet.",
};

export function ProjectsBoard({ projects }: { projects: ProjectRow[] }) {
  if (projects.length === 0) {
    return (
      <EmptyState title="No projects" icon={<FolderKanbanIcon />}>
        Projects an agent pushes (POST /ingest/projects) show up here, in a lane for each status.
      </EmptyState>
    );
  }
  let index = 0;
  return (
    <div className="grid grid-cols-1 items-start gap-4 md:grid-cols-2 xl:grid-cols-4">
      {projectLanes(projects).map((lane) => {
        const alert = lane.status === "blocked" && lane.projects.length > 0;
        return (
          <section
            key={lane.status}
            aria-label={`${lane.label}: ${plural(lane.projects.length, "project")}`}
            className={cn("flex flex-col gap-3 rounded-[28px] bg-foreground/[0.035] p-2.5", alert && "feed-alert bg-destructive/[0.05] dark:bg-destructive/[0.07]")}
          >
            <header className="flex items-center justify-between gap-2 px-2.5 pt-1.5 pb-0.5">
              <span className="flex items-center gap-2 text-sm font-semibold">
                <StatusDot state={LANE_DOT[lane.status]} pulse={false} />
                {lane.label}
              </span>
              <span className="rounded-full bg-foreground/8 px-2 text-xs tabular-nums text-muted-foreground">{lane.projects.length}</span>
            </header>
            {lane.projects.length === 0 ? (
              <p className="rounded-[20px] border border-dashed border-foreground/12 px-4 py-6 text-center text-[13px] text-muted-foreground">{EMPTY[lane.status]}</p>
            ) : (
              lane.projects.map((p) => <ProjectCard key={p.id} p={p} index={index++} />)
            )}
          </section>
        );
      })}
    </div>
  );
}

function ProjectCard({ p, index }: { p: ProjectRow; index: number }) {
  const color = cssColor(p.color) ?? cssColor(p.agent_color);
  const r = rise(index);
  const done = p.status === "done";
  return (
    <article className={cn(CARD, LIFT, "relative overflow-hidden rounded-[22px] p-4 pl-5", r.className)} style={r.style}>
      <span aria-hidden="true" className="absolute inset-y-0 left-0 w-1.5 bg-primary" style={color ? { background: color } : undefined} />
      <div className="flex items-start gap-3">
        <div className="min-w-0 flex-1">
          <h3 className="leading-snug font-semibold">
            <Link href={`/feed/projects/${p.id}`} className={cn(STRETCH, "text-foreground no-underline", done && "text-muted-foreground")}>
              {p.name}
            </Link>
          </h3>
          <div className="mt-0.5 flex items-center gap-1.5 text-xs text-muted-foreground">
            <span>{p.kind}</span>
            <span aria-hidden="true">·</span>
            <span className="truncate">{p.agent_name}</span>
            {p.link ? (
              <a
                href={p.link}
                target="_blank"
                rel="noopener noreferrer"
                className="relative z-10 -m-1 rounded p-1 hover:text-foreground"
                aria-label={`Open ${p.name}'s link`}
              >
                <ExternalLinkIcon className="size-3.5" />
              </a>
            ) : null}
          </div>
        </div>
        {p.progress != null ? (
          <RingGauge value={p.progress / 100} size={46} stroke={5} color={color} tone={done ? "up" : "neutral"} label={`${p.progress}% done`}>
            <span className="text-[11px] font-semibold tabular-nums">{p.progress}%</span>
          </RingGauge>
        ) : null}
      </div>
      {p.summary ? <p className="mt-2.5 line-clamp-2 text-[13px] text-muted-foreground">{p.summary}</p> : null}
      {p.next_step && !done ? (
        <p className="mt-2 text-[13px] leading-snug">
          <span className="font-medium">Next:</span> {p.next_step}
        </p>
      ) : null}
      {p.last_update ? (
        <div className="mt-3 flex items-baseline gap-3 border-t border-foreground/8 pt-2.5 text-xs text-muted-foreground">
          <span className="min-w-0 flex-1 truncate" title={p.last_update}>
            {p.last_update}
          </span>
          <Time iso={p.last_update_at} />
        </div>
      ) : null}
      {p.status === "blocked" ? <AskLink question={`Why is ${p.name} blocked, and what would unblock it?`} label="Ask why" className="mt-3" /> : null}
    </article>
  );
}
