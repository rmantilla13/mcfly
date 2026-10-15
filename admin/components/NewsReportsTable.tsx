import { NewspaperIcon, Trash2Icon } from "lucide-react";
import Link from "next/link";
import { ConfirmAction } from "@/components/ConfirmAction";
import { AgentLabel, EmptyState, Time, numCell } from "@/components/bits";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import type { FormAction } from "@/lib/action-result";
import { formatNumber, formatShortDate } from "@/lib/format";
import type { NewsReportRow } from "@/lib/types";

export function NewsReportsTable({ reports, deleteAction }: { reports: NewsReportRow[]; deleteAction: FormAction }) {
  if (reports.length === 0) {
    return (
      <EmptyState title="No reports" icon={<NewspaperIcon />}>
        Daily Pulse reports an agent pushes (POST /ingest/news) are listed here, newest first.
      </EmptyState>
    );
  }
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead className="pl-4">Report</TableHead>
          <TableHead>Sections</TableHead>
          <TableHead className={numCell}>Items</TableHead>
          <TableHead>Agent</TableHead>
          <TableHead>Published</TableHead>
          <TableHead className="w-12 pr-4">
            <span className="sr-only">Actions</span>
          </TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {reports.map((r) => (
          <TableRow key={r.id}>
            <TableCell className="pl-4">
              <Link href={`/feed/news/${r.id}`} className="font-medium text-foreground hover:underline">
                {r.display_date ?? formatShortDate(r.report_date)}
              </Link>
              <div className="font-mono text-xs text-muted-foreground">{r.slug}</div>
            </TableCell>
            <TableCell className="whitespace-normal">
              <div className="flex flex-wrap gap-1">
                {r.sections.map((s) => (
                  <Badge key={s} variant="outline">
                    {s}
                  </Badge>
                ))}
              </div>
            </TableCell>
            <TableCell className={numCell}>{formatNumber(r.item_count)}</TableCell>
            <TableCell>
              <AgentLabel name={r.agent_name} color={r.agent_color} />
            </TableCell>
            <TableCell>
              <Time iso={r.published_at} />
            </TableCell>
            <TableCell className="pr-4 text-right">
              <ConfirmAction
                action={deleteAction}
                fields={{ report_id: r.id, stay: "1" }}
                title={`Delete the ${r.slug} report?`}
                description={`Its ${formatNumber(r.item_count)} stories leave every display. The agent can push the report again.`}
                confirmLabel="Delete report"
                tone="danger"
                trigger={
                  <Button variant="ghost" size="icon-sm" aria-label={`Delete ${r.slug}`}>
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
