import { cn } from "cn";
import { ArrowDownRightIcon, ArrowUpRightIcon, MinusIcon } from "lucide-react";
import { AnimatedNumber } from "@/components/AnimatedNumber";
import { AreaChart, RingGauge, Sparkline as Spark, StatusDot } from "@/components/charts";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader } from "@/components/ui/card";
import { changeDirection, formatChange } from "@/lib/format";
import { goodDirection } from "@/lib/insights";
import type { Widget } from "@/lib/types";
import { formatMetricValue, progressPercent } from "@/lib/widgets";

// A dashboard's widgets, read-only, the way the display lays them out:
// one Card each. The shapes are lib/widgets.ts's; anything it couldn't
// read never gets here. Numbers count up, progress is a ring, a chart is a
// smooth area with its high, low and newest value, and a status that needs
// a look breathes. How wide each card is belongs to the page (widgetWide).

const STATE = {
  ok: { word: "OK", text: "text-success" },
  warn: { word: "Warning", text: "text-warning" },
  down: { word: "Down", text: "text-destructive" },
  unknown: { word: "Unknown", text: "text-muted-foreground" },
};

// The smooth line with its newest value beside it.
export function Sparkline({ points, unit }: { points: number[]; unit?: string }) {
  const last = points[points.length - 1];
  return (
    <div className="flex items-end gap-3">
      <Spark points={points} className="h-10 w-full max-w-[220px]" />
      {last !== undefined ? <span className="font-heading text-lg font-semibold tabular-nums">{formatMetricValue(last, unit)}</span> : null}
    </div>
  );
}

// "+46 (+4.2%)" as a chip with an arrow: green up, red down, grey flat.
// Green when the move is good news: a falling error rate or latency is.
function DeltaChip({ delta, pct, good = "up" }: { delta?: number; pct?: number; good?: "up" | "down" }) {
  const text = formatChange(delta, pct);
  if (text === "—") return null;
  const direction = changeDirection(delta, pct);
  const Icon = direction === "up" ? ArrowUpRightIcon : direction === "down" ? ArrowDownRightIcon : MinusIcon;
  return (
    <Badge variant={direction === "flat" ? "secondary" : direction === good ? "success" : "destructive"} className="tabular-nums">
      <Icon />
      {text}
    </Badge>
  );
}

export function WidgetCard({ widget, className }: { widget: Widget; className?: string }) {
  switch (widget.type) {
    case "metric":
      return (
        <Card size="sm" className={className}>
          <CardHeader>
            <CardDescription>{widget.label || "Metric"}</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col items-start gap-2">
            {/* Not a CardTitle: in a small card its text-sm outranks any size given here. */}
            <div className="font-heading text-[28px] leading-none font-semibold tracking-tight">
              <AnimatedNumber value={widget.value} format="metric" unit={widget.unit} />
            </div>
            <DeltaChip delta={widget.delta} pct={widget.delta_pct} good={goodDirection(widget.unit ?? null, widget.label ?? "")} />
          </CardContent>
        </Card>
      );
    case "status": {
      const { word, text } = STATE[widget.state];
      return (
        <Card size="sm" className={className}>
          <CardHeader>
            <CardDescription>{widget.label || "Status"}</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-1.5">
            <div className="flex items-center gap-2.5">
              <StatusDot state={widget.state} />
              <span className={cn("font-heading text-lg leading-none font-semibold", text)}>{word}</span>
            </div>
            {widget.detail ? <p className="text-sm text-muted-foreground">{widget.detail}</p> : null}
          </CardContent>
        </Card>
      );
    }
    case "progress": {
      const percent = progressPercent(widget.value, widget.max);
      const unitless = !widget.unit || widget.unit === "%";
      return (
        <Card size="sm" className={className}>
          <CardHeader>
            <CardDescription>{widget.label || "Progress"}</CardDescription>
          </CardHeader>
          <CardContent className="flex items-center gap-4">
            <RingGauge value={percent / 100} size={76} stroke={8} label={`${widget.label || "Progress"}: ${percent}%`}>
              <span className="font-heading text-base font-semibold tabular-nums">{percent}%</span>
            </RingGauge>
            <div className="flex min-w-0 flex-col gap-1">
              {unitless ? null : <span className="font-heading text-2xl leading-none font-semibold tabular-nums">{formatMetricValue(widget.value, widget.unit)}</span>}
              <span className={cn("tabular-nums", unitless ? "text-base font-medium" : "text-sm text-muted-foreground")}>
                {formatMetricValue(widget.value, null)} / {formatMetricValue(widget.max, widget.unit)}
              </span>
            </div>
          </CardContent>
        </Card>
      );
    }
    case "list":
      return (
        <Card size="sm" className={className}>
          <CardHeader>
            <CardDescription>{widget.title ?? "List"}</CardDescription>
          </CardHeader>
          <CardContent>
            {widget.items.length === 0 ? (
              <p className="text-sm text-muted-foreground">Nothing listed.</p>
            ) : (
              <ul className="flex flex-col gap-1.5 text-sm leading-snug">
                {widget.items.map((item, i) => (
                  <li key={i} className="flex gap-2.5">
                    <span className="mt-[6px] size-1.5 shrink-0 rounded-full bg-primary/50" aria-hidden="true" />
                    <span className="min-w-0 break-words">{item}</span>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      );
    case "text":
      return (
        <Card size="sm" className={className}>
          <CardHeader>
            <CardDescription>{widget.title ?? "Note"}</CardDescription>
          </CardHeader>
          <CardContent>
            <p className="text-sm leading-relaxed text-pretty whitespace-pre-line">{widget.body || <span className="text-muted-foreground">Empty.</span>}</p>
          </CardContent>
        </Card>
      );
    case "chart":
      return (
        <Card size="sm" className={className}>
          <CardHeader>
            <CardDescription>{widget.label || "Chart"}</CardDescription>
          </CardHeader>
          <CardContent>
            {widget.points.length === 0 ? (
              <p className="text-sm text-muted-foreground">No points.</p>
            ) : (
              <AreaChart points={widget.points} format="metric" unit={widget.unit} height={150} label={widget.label || "Chart"} />
            )}
          </CardContent>
        </Card>
      );
  }
}
