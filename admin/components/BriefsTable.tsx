import { FileTextIcon, Trash2Icon } from "lucide-react";
import { ConfirmAction } from "@/components/ConfirmAction";
import { AgentLabel, BriefKindBadge, EmptyState, Time } from "@/components/bits";
import { Button } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import type { FormAction } from "@/lib/action-result";
import { preview } from "@/lib/format";
import type { Brief } from "@/lib/types";

export function BriefsTable({ briefs, deleteAction }: { briefs: Brief[]; deleteAction: FormAction }) {
  if (briefs.length === 0) {
    return (
      <EmptyState title="No briefs" icon={<FileTextIcon />}>
        Briefs an agent pushes (POST /ingest/briefs) show up here, newest first.
      </EmptyState>
    );
  }
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead className="pl-4">Agent</TableHead>
          <TableHead>Kind</TableHead>
          <TableHead>Brief</TableHead>
          <TableHead>Published</TableHead>
          <TableHead className="w-12 pr-4">
            <span className="sr-only">Actions</span>
          </TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {briefs.map((b) => (
          <TableRow key={b.id}>
            <TableCell className="pl-4 font-medium">
              <AgentLabel name={b.agent_name} color={b.agent_color} />
            </TableCell>
            <TableCell>
              <BriefKindBadge kind={b.kind} />
            </TableCell>
            <TableCell className="max-w-xl whitespace-normal">
              <div className="font-medium">{b.title}</div>
              <div className="text-[13px] text-muted-foreground">{preview(b.body) || "—"}</div>
            </TableCell>
            <TableCell>
              <Time iso={b.published_at} />
              {b.expires_at ? (
                <div className="text-xs text-muted-foreground">
                  expires <Time iso={b.expires_at} />
                </div>
              ) : null}
            </TableCell>
            <TableCell className="pr-4 text-right">
              <ConfirmAction
                action={deleteAction}
                fields={{ brief_id: b.id }}
                title="Delete this brief?"
                description={<>&ldquo;{b.title}&rdquo; disappears from every display. The agent can push it again.</>}
                confirmLabel="Delete"
                tone="danger"
                trigger={
                  <Button variant="ghost" size="icon-sm" aria-label={`Delete ${b.title}`}>
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
