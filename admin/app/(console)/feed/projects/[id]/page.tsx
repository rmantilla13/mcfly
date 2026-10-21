import { cn } from "cn";
import { ChevronLeftIcon, ExternalLinkIcon, FolderKanbanIcon, Trash2Icon } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { deleteProjectAction } from "@/app/(console)/actions";
import { ConfirmAction } from "@/components/ConfirmAction";
import { PageHeader } from "@/components/PageHeader";
import { ActivityStrip, ProjectTimeline } from "@/components/ProjectTimeline";
import { StageSteps } from "@/components/StageTrack";
import { AgentLabel, EmptyState, ProjectKindBadge, ProjectStatusBadge, Time } from "@/components/bits";
import { RingGauge } from "@/components/charts";
import { AskLink } from "@/components/feed/bits";
import { CARD, rise } from "@/components/feed/styles";
import { Button } from "@/components/ui/button";
import { getProject, getProjectUpdates, getSettings, requireAdmin } from "@/lib/data";
import { safeTimeZone } from "@/lib/events";
import { stageTrack, timeInStage } from "@/lib/feed-layout";
import { cssColor, formatNumber, plural } from "@/lib/format";
import type { ProjectUpdateKind } from "@/lib/types";

type Props = { params: Promise<{ id: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const project = await getProject((await params).id);
  return { title: project ? `${project.name} · Projects` : "Project" };
}

const KIND_WORD: Record<ProjectUpdateKind, string> = {
  commit: "commits",
  pr: "pull requests",
  ci: "CI runs",
  deploy: "deploys",
  alert: "alerts",
  done: "done",
  note: "notes",
};

// Its updates and the display's zone, and the time they were read at (the
// month's strip ends on that day).
async function history(id: string) {
  const [updates, settings] = await Promise.all([getProjectUpdates(id, 100), getSettings()]);
  return { updates, settings, now: Date.now() };
}

// A project: where it stands (its progress as a big ring, what it is and
// what's next), its stages (when the agent sends them) as steps from the
// first to the last, its last month as a strip of days, and its history as
// a timeline, newest first.
export default async function ProjectPage({ params }: Props) {
  await requireAdmin();
  const project = await getProject((await params).id);
  if (!project) notFound();
  const { updates, settings, now } = await history(project.id);
  const timeZone = safeTimeZone(settings.timezone);
  const color = cssColor(project.color) ?? cssColor(project.agent_color);
  // What kind of work the history is made of, busiest first.
  const kinds = [...updates.reduce((m, u) => m.set(u.kind, (m.get(u.kind) ?? 0) + 1), new Map<ProjectUpdateKind, number>())].sort((a, b) => b[1] - a[1]);
  const track = stageTrack(project);
  const inStage = track?.current && project.status !== "done" ? timeInStage(project.stage_since, now) : "";

  return (
    <>
      <PageHeader
        eyebrow={
          <Link href="/feed?tab=projects" className="inline-flex items-center gap-1 text-muted-foreground no-underline hover:text-foreground">
            <ChevronLeftIcon className="size-3.5" /> Projects
          </Link>
        }
        title={
          <span className="inline-flex flex-wrap items-center gap-3">
            {project.name}
            <ProjectStatusBadge status={project.status} />
            <ProjectKindBadge kind={project.kind} />
          </span>
        }
        subtitle={
          <span className="inline-flex flex-wrap items-center gap-x-3 gap-y-1">
            <AgentLabel name={project.agent_name} color={project.agent_color} />
            <span>
              key <code className="font-mono">{project.key}</code>
            </span>
            <span>
              updated <Time iso={project.updated_at} />
            </span>
            {project.link ? (
              <a href={project.link} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1">
                {project.link.replace(/^https?:\/\//, "")}
                <ExternalLinkIcon className="size-3" />
              </a>
            ) : null}
          </span>
        }
        actions={
          <ConfirmAction
            action={deleteProjectAction}
            fields={{ project_id: project.id }}
            title={`Delete ${project.name}?`}
            description={`The project and its ${plural(updates.length, "update")} are removed. The agent's next push brings it back as new.`}
            confirmLabel="Delete project"
            tone="danger"
            trigger={
              <Button variant="destructive">
                <Trash2Icon data-icon="inline-start" />
                Delete project
              </Button>
            }
          />
        }
      />

      <div className="flex flex-col gap-5">
        <section
          className={cn(CARD, "relative grid grid-cols-1 items-center gap-6 overflow-hidden p-6 sm:grid-cols-[auto_minmax(0,1fr)] max-sm:p-5", rise(0).className)}
          style={rise(0).style}
          aria-labelledby="stands-title"
        >
          <span aria-hidden="true" className="absolute inset-y-0 left-0 w-1.5 bg-primary" style={color ? { background: color } : undefined} />
          {project.progress != null ? (
            <RingGauge value={project.progress / 100} size={140} stroke={12} color={color} label={`${project.progress}% done`} className="max-sm:mx-auto">
              <span className="font-heading text-[34px] leading-none font-semibold tracking-tight tabular-nums">{project.progress}%</span>
              <span className="mt-1.5 text-xs font-medium text-muted-foreground">done</span>
            </RingGauge>
          ) : null}
          <div className={cn("flex min-w-0 flex-col gap-3", project.progress == null && "sm:col-span-2")}>
            <h2 id="stands-title" className="text-xs font-semibold tracking-wider text-muted-foreground uppercase">
              Where it stands
            </h2>
            <p className="text-[17px] leading-relaxed text-pretty whitespace-pre-line">{project.summary || <span className="text-muted-foreground">No summary.</span>}</p>
            {project.next_step ? (
              <div className="flex items-start gap-3 rounded-2xl bg-accent/60 px-4 py-3 text-[15px] text-accent-foreground dark:bg-accent/40">
                <span className="font-semibold">Next</span>
                <span className="min-w-0 text-foreground">{project.next_step}</span>
              </div>
            ) : null}
            <div className="flex flex-wrap items-center gap-x-4 gap-y-2 text-[13px] text-muted-foreground">
              <span>{plural(project.update_count, "update")}</span>
              {project.last_update_at ? (
                <span>
                  last <Time iso={project.last_update_at} />
                </span>
              ) : null}
              {project.status === "blocked" ? (
                <AskLink question={`Why is ${project.name} blocked, and what would unblock it?`} label="Ask why it's blocked" />
              ) : (
                <AskLink question={`Where does ${project.name} stand, and what's next?`} label="Ask for a summary" />
              )}
            </div>
          </div>
        </section>

        {track ? (
          <section className={cn(CARD, "flex flex-col gap-5 p-6 max-sm:p-5", rise(1).className)} style={rise(1).style} aria-labelledby="stages-title">
            <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
              <div>
                <h2 id="stages-title" className="font-heading text-base font-semibold">
                  Stages
                </h2>
                <p className="mt-0.5 text-[13px] text-muted-foreground">
                  {track.headline}
                  {inStage ? ` for ${inStage}` : ""}
                </p>
              </div>
              <span className="text-[13px] text-muted-foreground tabular-nums">{track.position}</span>
            </div>
            <StageSteps track={track} color={color} />
          </section>
        ) : null}

        <div className="grid grid-cols-1 items-start gap-5 lg:grid-cols-[minmax(0,1fr)_340px]">
          <section className={cn(CARD, "flex flex-col gap-4 p-6 max-sm:p-5 lg:order-2", rise(1).className)} style={rise(1).style} aria-labelledby="month-title">
            <div>
              <h2 id="month-title" className="font-heading text-base font-semibold">
                The last 30 days
              </h2>
              <p className="mt-0.5 text-[13px] text-muted-foreground">A day each, darker the busier, in {timeZone}.</p>
            </div>
            <ActivityStrip updates={updates} timeZone={timeZone} color={color} now={now} />
            {kinds.length ? (
              <ul className="flex flex-col gap-1.5 border-t border-foreground/8 pt-4 text-[13px]">
                {kinds.map(([kind, n]) => (
                  <li key={kind} className="flex items-baseline justify-between gap-3">
                    <span className="text-muted-foreground">{kind === "done" ? "Marked done" : KIND_WORD[kind] ? KIND_WORD[kind][0].toUpperCase() + KIND_WORD[kind].slice(1) : kind}</span>
                    <span className="font-medium tabular-nums">{formatNumber(n)}</span>
                  </li>
                ))}
              </ul>
            ) : null}
          </section>

          <section className={cn(CARD, "flex flex-col gap-4 p-6 max-sm:p-5 lg:order-1", rise(2).className)} style={rise(2).style} aria-labelledby="updates-title">
            <div>
              <h2 id="updates-title" className="font-heading text-base font-semibold">
                Updates
              </h2>
              <p className="mt-0.5 text-[13px] text-muted-foreground">{plural(updates.length, "update")}, newest first. A project keeps its last 200.</p>
            </div>
            {updates.length === 0 ? (
              <EmptyState title="No updates yet" icon={<FolderKanbanIcon />}>
                Commits, pull requests, CI runs, deploys and notes the agent sends with the project show up here.
              </EmptyState>
            ) : (
              <ProjectTimeline updates={updates} timeZone={timeZone} now={now} />
            )}
          </section>
        </div>
      </div>
    </>
  );
}
