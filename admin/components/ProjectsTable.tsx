import { ExternalLinkIcon, FolderKanbanIcon, Trash2Icon } from "lucide-react";
import Link from "next/link";
import { ConfirmAction } from "@/components/ConfirmAction";
import { EmptyState, ProjectKindBadge, ProjectStatusBadge, Swatch, Time, numCell } from "@/components/bits";
import { Button } from "@/components/ui/button";
import { Progress } from "@/components/ui/progress";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import type { FormAction } from "@/lib/action-result";
import { formatNumber, preview } from "@/lib/format";
import type { ProjectRow } from "@/lib/types";

export function ProjectsTable({ projects, deleteAction }: { projects: ProjectRow[]; deleteAction: FormAction }) {
  if (projects.length === 0) {
    return (
      <EmptyState title="No projects" icon={<FolderKanbanIcon />}>
        Projects an agent pushes (POST /ingest/projects) are listed here, done ones last.
      </EmptyState>
    );
  }
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead className="pl-4">Project</TableHead>
          <TableHead>Status</TableHead>
          <TableHead>Progress</TableHead>
          <TableHead>Summary</TableHead>
          <TableHead>Last update</TableHead>
          <TableHead className={numCell}>Updates</TableHead>
          <TableHead className="w-12 pr-4">
            <span className="sr-only">Actions</span>
          </TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {projects.map((p) => (
          <TableRow key={p.id} className={p.status === "done" ? "text-muted-foreground" : undefined}>
            <TableCell className="pl-4">
              <div className="flex items-center gap-2.5">
                <Swatch color={p.color ?? p.agent_color} className="size-3.5" />
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <Link href={`/feed/projects/${p.id}`} className="truncate font-medium text-foreground hover:underline">
                      {p.name}
                    </Link>
                    <ProjectKindBadge kind={p.kind} />
                    {p.link ? (
                      <a href={p.link} target="_blank" rel="noopener noreferrer" className="text-muted-foreground hover:text-foreground" aria-label={`Open ${p.name}'s link`}>
                        <ExternalLinkIcon className="size-3.5" />
                      </a>
                    ) : null}
                  </div>
                  <div className="text-xs text-muted-foreground">
                    {p.agent_name} · <span className="font-mono">{p.key}</span>
                  </div>
                </div>
              </div>
            </TableCell>
            <TableCell>
              <ProjectStatusBadge status={p.status} />
            </TableCell>
            <TableCell>
              {p.progress == null ? (
                <span className="text-muted-foreground">—</span>
              ) : (
                <div className="flex w-28 items-center gap-2">
                  <Progress value={p.progress} aria-label={`${p.progress}% done`} />
                  <span className="text-xs tabular-nums">{p.progress}%</span>
                </div>
              )}
            </TableCell>
            <TableCell className="min-w-[260px] max-w-sm whitespace-normal">
              <div className="text-sm">{preview(p.summary, 120) || <span className="text-muted-foreground">—</span>}</div>
              {p.next_step ? (
                <div className="text-[13px] text-muted-foreground">
                  <span className="font-medium">Next:</span> {preview(p.next_step, 100)}
                </div>
              ) : null}
            </TableCell>
            <TableCell className="min-w-[180px] max-w-xs whitespace-normal">
              {p.last_update ? (
                <>
                  <div className="truncate text-sm" title={p.last_update}>
                    {preview(p.last_update, 80)}
                  </div>
                  <div className="text-xs text-muted-foreground">
                    <Time iso={p.last_update_at} />
                  </div>
                </>
              ) : (
                <span className="text-muted-foreground">none yet</span>
              )}
            </TableCell>
            <TableCell className={numCell}>{formatNumber(p.update_count)}</TableCell>
            <TableCell className="pr-4 text-right">
              <ConfirmAction
                action={deleteAction}
                fields={{ project_id: p.id, stay: "1" }}
                title={`Delete ${p.name}?`}
                description={`The project and its ${formatNumber(p.update_count)} updates are removed. The agent's next push brings it back as new.`}
                confirmLabel="Delete project"
                tone="danger"
                trigger={
                  <Button variant="ghost" size="icon-sm" aria-label={`Delete ${p.name}`}>
                    <Trash2Icon />
                  </Button>
                }
              />
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
