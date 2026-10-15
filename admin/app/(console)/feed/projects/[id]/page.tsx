import { ChevronLeftIcon, ExternalLinkIcon, FolderKanbanIcon, Trash2Icon } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { deleteProjectAction } from "@/app/(console)/actions";
import { ConfirmAction } from "@/components/ConfirmAction";
import { PageHeader } from "@/components/PageHeader";
import { AgentLabel, EmptyState, ProjectKindBadge, ProjectStatusBadge, Time, UpdateKindBadge, numCell } from "@/components/bits";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { getProject, getProjectUpdates, requireAdmin } from "@/lib/data";
import { formatDateTime, plural } from "@/lib/format";

type Props = { params: Promise<{ id: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const project = await getProject((await params).id);
  return { title: project ? `${project.name} · Projects` : "Project" };
}

export default async function ProjectPage({ params }: Props) {
  await requireAdmin();
  const project = await getProject((await params).id);
  if (!project) notFound();
  const updates = await getProjectUpdates(project.id, 100);

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
        <Card>
          <CardHeader>
            <CardTitle>Where it stands</CardTitle>
            {project.progress != null ? <CardDescription>{project.progress}% done</CardDescription> : null}
          </CardHeader>
          <CardContent className="flex flex-col gap-4">
            {project.progress != null ? <Progress value={project.progress} aria-label={`${project.progress}% done`} /> : null}
            <p className="text-sm whitespace-pre-line">{project.summary || <span className="text-muted-foreground">No summary.</span>}</p>
            {project.next_step ? (
              <p className="text-sm">
                <span className="font-medium">Next step:</span> {project.next_step}
              </p>
            ) : null}
          </CardContent>
        </Card>

        <Card className="gap-0 py-0">
          <CardHeader className="border-b py-4">
            <CardTitle>Updates</CardTitle>
            <CardDescription>{plural(updates.length, "update")}, newest first. A project keeps its last 200.</CardDescription>
          </CardHeader>
          <CardContent className="px-0 pt-2 pb-2">
            {updates.length === 0 ? (
              <EmptyState title="No updates yet" icon={<FolderKanbanIcon />}>
                Commits, pull requests, CI runs, deploys and notes the agent sends with the project show up here.
              </EmptyState>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead className="pl-4">Kind</TableHead>
                    <TableHead>Update</TableHead>
                    <TableHead className={`${numCell} pr-4`}>When</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {updates.map((u) => (
                    <TableRow key={u.id}>
                      <TableCell className="pl-4">
                        <UpdateKindBadge kind={u.kind} />
                      </TableCell>
                      <TableCell className="max-w-xl whitespace-normal">
                        {u.url ? (
                          <a href={u.url} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 hover:underline">
                            {u.text}
                            <ExternalLinkIcon className="size-3 text-muted-foreground" />
                          </a>
                        ) : (
                          u.text
                        )}
                      </TableCell>
                      <TableCell className={`${numCell} pr-4`}>
                        <Time iso={u.happened_at} />
                        <div className="text-xs text-muted-foreground">{formatDateTime(u.happened_at)}</div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>
      </div>
    </>
  );
}
