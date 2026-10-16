import { cn } from "cn";
import { StatusDot } from "@/components/charts";
import { Card, CardContent, CardDescription, CardHeader } from "@/components/ui/card";
import type { Widget } from "@/lib/types";

// A dashboard's run of status widgets as one strip (lib/feed-layout.ts
// widgetBlocks): a dot, the name and the state for each, and up top how
// many need a look. A dot that needs a look breathes; OK ones stay still.

type Status = Extract<Widget, { type: "status" }>;

const STATE = {
  ok: { word: "OK", text: "text-success" },
  warn: { word: "Warning", text: "text-warning" },
  down: { word: "Down", text: "text-destructive" },
  unknown: { word: "Unknown", text: "text-muted-foreground" },
};

export function HealthStrip({ items, className }: { items: Status[]; className?: string }) {
  const needs = items.filter((i) => i.state === "warn" || i.state === "down").length;
  return (
    <Card size="sm" className={className}>
      <CardHeader className="flex items-center justify-between gap-3">
        <CardDescription>Health</CardDescription>
        <span className={cn("text-xs font-medium", needs ? "text-warning" : "text-success")}>
          {needs ? `${needs} of ${items.length} need${needs === 1 ? "s" : ""} a look` : `All ${items.length} OK`}
        </span>
      </CardHeader>
      <CardContent>
        <ul className="grid grid-cols-1 gap-x-6 gap-y-4 sm:grid-cols-2 lg:grid-cols-4">
          {items.map((w, i) => {
            const { word, text } = STATE[w.state] ?? STATE.unknown;
            return (
              <li key={i} className="flex min-w-0 items-start gap-3">
                <StatusDot state={w.state} className="mt-[7px]" label={`${w.label || "Status"}: ${word}`} />
                <div className="min-w-0">
                  <div className="flex items-baseline gap-2">
                    <span className="truncate font-medium">{w.label || "Status"}</span>
                    <span className={cn("text-sm font-semibold", text)}>{word}</span>
                  </div>
                  {w.detail ? <p className="text-[13px] text-muted-foreground">{w.detail}</p> : null}
                </div>
              </li>
            );
          })}
        </ul>
      </CardContent>
    </Card>
  );
}
