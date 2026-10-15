"use client";

import { GaugeIcon, Trash2Icon } from "lucide-react";
import { Fragment, useId } from "react";
import { toast } from "sonner";
import { ConfirmAction } from "@/components/ConfirmAction";
import { AgentLabel, Delta, EmptyState, Time, numCell } from "@/components/bits";
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
import type { MetricRow } from "@/lib/types";
import { formatMetricValue } from "@/lib/widgets";

// Metrics grouped as the display groups them: by group_name, hidden ones
// after everything else (the RPC's order), with a heading row per group.
export function MetricsTable({ metrics, setAction, deleteAction }: { metrics: MetricRow[]; setAction: FormAction; deleteAction: FormAction }) {
  if (metrics.length === 0) {
    return (
      <EmptyState title="No metrics" icon={<GaugeIcon />}>
        Every metric an agent pushes (POST /ingest/metrics) is listed here by group, in display order.
      </EmptyState>
    );
  }
  const groups: { key: string; label: string; hidden: boolean; rows: MetricRow[] }[] = [];
  for (const m of metrics) {
    const name = m.group_name ?? "Ungrouped";
    const key = `${m.hidden ? "hidden:" : ""}${name}`;
    const last = groups[groups.length - 1];
    if (last?.key === key) last.rows.push(m);
    else groups.push({ key, label: name, hidden: m.hidden, rows: [m] });
  }
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead className="pl-4">Metric</TableHead>
          <TableHead className={numCell}>Value</TableHead>
          <TableHead className={numCell}>Change</TableHead>
          <TableHead className={numCell}>History</TableHead>
          <TableHead>On the display</TableHead>
          <TableHead className="w-12 pr-4">
            <span className="sr-only">Actions</span>
          </TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {groups.map((g) => (
          <Fragment key={g.key}>
            <TableRow className="bg-muted/40 hover:bg-muted/40">
              <TableCell colSpan={6} className="py-1.5 pl-4 text-xs font-semibold tracking-wider text-muted-foreground uppercase">
                {g.label}
                {g.hidden ? " · hidden" : ""}
              </TableCell>
            </TableRow>
            {g.rows.map((m) => (
              <MetricRowItem key={m.key} m={m} setAction={setAction} deleteAction={deleteAction} />
            ))}
          </Fragment>
        ))}
      </TableBody>
    </Table>
  );
}

function MetricRowItem({ m, setAction, deleteAction }: { m: MetricRow; setAction: FormAction; deleteAction: FormAction }) {
  const id = useId();
  const { result, pending, submit } = useFormAction(setAction, (res) => {
    if (res?.ok && res.message) toast.success(res.message);
  });
  return (
    <TableRow className={m.hidden ? "text-muted-foreground" : undefined}>
      <TableCell className="pl-4">
        <div className="flex items-center gap-2">
          <span className="font-medium text-foreground">{m.label}</span>
          {m.hidden ? <Badge variant="warning">Hidden</Badge> : null}
        </div>
        <div className="flex items-center gap-2 text-xs text-muted-foreground">
          <span className="font-mono">{m.key}</span>
          {m.agent_name ? (
            <>
              <span aria-hidden="true">·</span>
              <AgentLabel name={m.agent_name} color={m.agent_color} />
            </>
          ) : null}
        </div>
        {m.note ? (
          <div className="max-w-xs truncate text-xs text-muted-foreground" title={m.note}>
            {m.note}
          </div>
        ) : null}
      </TableCell>
      <TableCell className={`${numCell} font-medium text-foreground`}>
        {formatMetricValue(m.value, m.unit)}
        <div className="text-xs font-normal text-muted-foreground">
          <Time iso={m.as_of} fallback="no value" />
        </div>
      </TableCell>
      <TableCell className={numCell}>
        <Delta delta={m.delta} pct={m.delta_pct} />
      </TableCell>
      <TableCell className={numCell}>{formatNumber(m.history_count)}</TableCell>
      <TableCell>
        {/* One small form per row, as admin_set_metric takes it. Blank label
            or group keeps what is there. */}
        <form onSubmit={submit} className="flex max-w-[400px] flex-col gap-1">
          <input type="hidden" name="metric" value={m.key} />
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1.5">
            <Label htmlFor={`${id}-hidden`} className="gap-1.5">
              <Switch id={`${id}-hidden`} name="hidden" defaultChecked={m.hidden} size="sm" />
              hidden
            </Label>
            <Label htmlFor={`${id}-order`} className="gap-1.5">
              order
              <Input id={`${id}-order`} name="sort_order" type="number" defaultValue={m.sort_order} min={-100000} max={100000} step={1} className="h-7 w-16 text-sm" />
            </Label>
            <Input name="label" defaultValue={m.label} maxLength={80} placeholder="Label" aria-label="Label" className="h-7 w-28 text-sm" />
            <Input name="group_name" defaultValue={m.group_name ?? ""} maxLength={80} placeholder="Group" aria-label="Group" className="h-7 w-24 text-sm" />
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
          fields={{ metric: m.key }}
          title={`Delete ${m.label}?`}
          description={`${formatNumber(m.history_count)} rows of history go with it. An agent that pushes ${m.key} again brings it back, ungrouped.`}
          confirmLabel="Delete metric"
          tone="danger"
          trigger={
            <Button variant="ghost" size="icon-sm" aria-label={`Delete ${m.label}`}>
              <Trash2Icon />
            </Button>
          }
        />
      </TableCell>
    </TableRow>
  );
}
