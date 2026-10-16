import { ActivityIcon } from "lucide-react";
import { AgentLabel, EmptyState, Time, numCell } from "@/components/bits";
import { StatusBadge } from "@/components/StatusBadge";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { formatNumber } from "@/lib/format";
import type { IngestEntry } from "@/lib/types";

// The ingest log: one row per push, newest first.
export function IngestTable({ entries }: { entries: IngestEntry[] }) {
  if (entries.length === 0) {
    return (
      <EmptyState title="No pushes yet" icon={<ActivityIcon />}>
        Every push an agent makes shows up here, including the ones the ingest function refused.
      </EmptyState>
    );
  }
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead className="pl-4">Agent</TableHead>
          <TableHead>Feed</TableHead>
          <TableHead className={numCell}>Items</TableHead>
          <TableHead>Status</TableHead>
          <TableHead>Message</TableHead>
          <TableHead className={`${numCell} pr-4`}>When</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {entries.map((e) => (
          <TableRow key={e.id}>
            <TableCell className="pl-4 font-medium">
              <AgentLabel name={e.agent_name ?? "Unknown agent"} color={e.agent_color} />
            </TableCell>
            <TableCell>
              <Badge variant="outline">{e.feed}</Badge>
            </TableCell>
            <TableCell className={numCell}>{formatNumber(e.count)}</TableCell>
            <TableCell>
              <StatusBadge status={e.status} />
            </TableCell>
            <TableCell className="max-w-md truncate whitespace-normal text-muted-foreground" title={e.message ?? undefined}>
              {e.message ?? "—"}
            </TableCell>
            <TableCell className={`${numCell} pr-4`}>
              <Time iso={e.created_at} />
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
