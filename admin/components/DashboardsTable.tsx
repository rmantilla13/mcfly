"use client";

import { LayoutDashboardIcon, Trash2Icon } from "lucide-react";
import Link from "next/link";
import { useId } from "react";
import { toast } from "sonner";
import { ConfirmAction } from "@/components/ConfirmAction";
import { AgentLabel, EmptyState, Time, numCell } from "@/components/bits";
import { useFormAction } from "@/components/useFormAction";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { FieldError } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Spinner } from "@/components/ui/spinner";
import { Switch } from "@/components/ui/switch";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import type { FormAction } from "@/lib/action-result";
import { formatNumber } from "@/lib/format";
import type { DashboardRow } from "@/lib/types";

export function DashboardsTable({ dashboards, setAction, deleteAction }: { dashboards: DashboardRow[]; setAction: FormAction; deleteAction: FormAction }) {
  if (dashboards.length === 0) {
    return (
      <EmptyState title="No dashboards" icon={<LayoutDashboardIcon />}>
        Dashboards an agent lays out (POST /ingest/dashboards) are listed here, in display order.
      </EmptyState>
    );
  }
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead className="pl-4">Dashboard</TableHead>
          <TableHead>Agent</TableHead>
          <TableHead className={numCell}>Widgets</TableHead>
          <TableHead>Updated</TableHead>
          <TableHead>On the display</TableHead>
          <TableHead className="w-12 pr-4">
            <span className="sr-only">Actions</span>
          </TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {dashboards.map((d) => (
          <DashboardRowItem key={d.id} d={d} setAction={setAction} deleteAction={deleteAction} />
        ))}
      </TableBody>
    </Table>
  );
}

function DashboardRowItem({ d, setAction, deleteAction }: { d: DashboardRow; setAction: FormAction; deleteAction: FormAction }) {
  const id = useId();
  const { result, pending, submit } = useFormAction(setAction, (res) => {
    if (res?.ok && res.message) toast.success(res.message);
  });
  return (
    <TableRow className={d.hidden ? "text-muted-foreground" : undefined}>
      <TableCell className="pl-4">
        <div className="flex items-center gap-2">
          <Link href={`/feed/dashboards/${d.id}`} className="font-medium text-foreground hover:underline">
            {d.title}
          </Link>
          {d.hidden ? <Badge variant="warning">Hidden</Badge> : null}
        </div>
        <div className="text-xs text-muted-foreground">
          <span className="font-mono">{d.key}</span>
          {d.subtitle ? ` · ${d.subtitle}` : ""}
        </div>
      </TableCell>
      <TableCell>
        <AgentLabel name={d.agent_name} color={d.agent_color} />
      </TableCell>
      <TableCell className={numCell}>{formatNumber(d.widgets.length)}</TableCell>
      <TableCell>
        <Time iso={d.updated_at} />
      </TableCell>
      <TableCell>
        <form onSubmit={submit} className="flex max-w-[300px] flex-col gap-1">
          <input type="hidden" name="dashboard_id" value={d.id} />
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1.5">
            <Label htmlFor={`${id}-hidden`} className="gap-1.5">
              <Switch id={`${id}-hidden`} name="hidden" defaultChecked={d.hidden} size="sm" />
              hidden
            </Label>
            <Label htmlFor={`${id}-order`} className="gap-1.5">
              order
              <Input id={`${id}-order`} name="sort_order" type="number" defaultValue={d.sort_order} min={-100000} max={100000} step={1} className="h-7 w-16 text-sm" />
            </Label>
            <Button type="submit" variant="outline" size="sm" disabled={pending}>
              {pending ? <Spinner data-icon="inline-start" /> : null}
              Save
            </Button>
          </div>
          {result && !result.ok ? <FieldError>{result.error}</FieldError> : null}
        </form>
      </TableCell>
      <TableCell className="pr-4 text-right">
        <ConfirmAction
          action={deleteAction}
          fields={{ dashboard_id: d.id, stay: "1" }}
          title={`Delete ${d.title}?`}
          description="The dashboard leaves every display. The agent's next push brings it back."
          confirmLabel="Delete dashboard"
          tone="danger"
          trigger={
            <Button variant="ghost" size="icon-sm" aria-label={`Delete ${d.title}`}>
              <Trash2Icon />
            </Button>
          }
        />
      </TableCell>
    </TableRow>
  );
}
