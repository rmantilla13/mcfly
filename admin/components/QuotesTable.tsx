"use client";

import { cn } from "cn";
import { Trash2Icon, TrendingUpIcon } from "lucide-react";
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
import { changeDirection, formatChange, formatNumber, formatPrice } from "@/lib/format";
import type { QuoteRow } from "@/lib/types";

export function QuotesTable({ quotes, setAction, deleteAction }: { quotes: QuoteRow[]; setAction: FormAction; deleteAction: FormAction }) {
  if (quotes.length === 0) {
    return (
      <EmptyState title="No symbols" icon={<TrendingUpIcon />}>
        Every symbol an agent pushes (POST /ingest/quotes) is listed here, in the order the display shows it.
      </EmptyState>
    );
  }
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead className="pl-4">Symbol</TableHead>
          <TableHead className={numCell}>Price</TableHead>
          <TableHead className={numCell}>Change</TableHead>
          <TableHead className={numCell}>History</TableHead>
          <TableHead>On the display</TableHead>
          <TableHead className="w-12 pr-4">
            <span className="sr-only">Actions</span>
          </TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {quotes.map((q) => (
          <SymbolRow key={q.symbol} q={q} setAction={setAction} deleteAction={deleteAction} />
        ))}
      </TableBody>
    </Table>
  );
}

function SymbolRow({ q, setAction, deleteAction }: { q: QuoteRow; setAction: FormAction; deleteAction: FormAction }) {
  const id = useId();
  const { result, pending, submit } = useFormAction(setAction, (res) => {
    if (res?.ok && res.message) toast.success(res.message);
  });
  const direction = changeDirection(q.change, q.change_pct);
  return (
    <TableRow className={q.hidden ? "text-muted-foreground" : undefined}>
      <TableCell className="pl-4">
        <div className="flex items-center gap-2">
          <span className="font-mono font-semibold text-foreground">{q.symbol}</span>
          {q.hidden ? <Badge variant="warning">Hidden</Badge> : null}
        </div>
        <div className="flex items-center gap-2 text-[13px] text-muted-foreground">
          <span>{q.name ?? "—"}</span>
          {q.agent_name ? (
            <>
              <span aria-hidden="true">·</span>
              <AgentLabel name={q.agent_name} color={q.agent_color} />
            </>
          ) : null}
        </div>
        {q.note ? <div className="max-w-xs truncate text-xs text-muted-foreground" title={q.note}>{q.note}</div> : null}
      </TableCell>
      <TableCell className={`${numCell} font-medium text-foreground`}>
        {formatPrice(q.price, q.currency)}
        <div className="text-xs font-normal text-muted-foreground">
          <Time iso={q.as_of} fallback="no quote" />
        </div>
      </TableCell>
      <TableCell className={cn(numCell, direction === "up" && "text-success", direction === "down" && "text-destructive")}>
        {formatChange(q.change, q.change_pct)}
      </TableCell>
      <TableCell className={numCell}>{formatNumber(q.history_count)}</TableCell>
      <TableCell>
        {/* One small form per row: hidden and sort order, as admin_set_symbol takes them. */}
        <form onSubmit={submit} className="flex max-w-[300px] flex-col gap-1">
          <input type="hidden" name="symbol" value={q.symbol} />
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1.5">
            <Label htmlFor={`${id}-shown`} className="gap-1.5">
              <Switch id={`${id}-shown`} name="hidden" defaultChecked={q.hidden} size="sm" />
              hidden
            </Label>
            <Label htmlFor={`${id}-order`} className="gap-1.5">
              order
              <Input id={`${id}-order`} name="sort_order" type="number" defaultValue={q.sort_order} min={-100000} max={100000} step={1} className="h-7 w-16 text-sm" />
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
          fields={{ symbol: q.symbol }}
          title={`Delete ${q.symbol}?`}
          description={`${formatNumber(q.history_count)} quotes go with it. An agent that pushes ${q.symbol} again brings it back, at the end of the list.`}
          confirmLabel="Delete symbol"
          tone="danger"
          trigger={
            <Button variant="ghost" size="icon-sm" aria-label={`Delete ${q.symbol}`}>
              <Trash2Icon />
            </Button>
          }
        />
      </TableCell>
    </TableRow>
  );
}
