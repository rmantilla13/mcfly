import { CheckCircle2Icon, CircleAlertIcon, CircleHelpIcon, CircleXIcon } from "lucide-react";
import { Delta } from "@/components/bits";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import type { Widget } from "@/lib/types";
import { formatMetricValue, progressPercent, sparklinePath } from "@/lib/widgets";

// A dashboard's widgets, read-only, the way the display lays them out:
// one Card each. The shapes are lib/widgets.ts's; anything it couldn't
// read never gets here.

const STATE = {
  ok: { variant: "success" as const, Icon: CheckCircle2Icon, word: "OK" },
  warn: { variant: "warning" as const, Icon: CircleAlertIcon, word: "Warning" },
  down: { variant: "destructive" as const, Icon: CircleXIcon, word: "Down" },
  unknown: { variant: "outline" as const, Icon: CircleHelpIcon, word: "Unknown" },
};

export function Sparkline({ points, unit }: { points: number[]; unit?: string }) {
  const width = 120;
  const height = 32;
  const path = sparklinePath(points, width, height);
  const last = points[points.length - 1];
  return (
    <div className="flex items-end gap-3">
      <svg viewBox={`0 0 ${width} ${height}`} className="h-10 w-full max-w-[220px] text-primary" preserveAspectRatio="none" aria-hidden="true">
        <path d={path} fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinejoin="round" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
      </svg>
      {last !== undefined ? <span className="font-heading text-lg font-semibold tabular-nums">{formatMetricValue(last, unit)}</span> : null}
    </div>
  );
}

export function WidgetCard({ widget }: { widget: Widget }) {
  switch (widget.type) {
    case "metric":
      return (
        <Card size="sm">
          <CardHeader>
            <CardDescription>{widget.label || "Metric"}</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-1">
            <CardTitle className="font-heading text-2xl font-semibold tabular-nums">{formatMetricValue(widget.value, widget.unit)}</CardTitle>
            <Delta delta={widget.delta} pct={widget.delta_pct} className="text-sm" />
          </CardContent>
        </Card>
      );
    case "status": {
      const { variant, Icon, word } = STATE[widget.state];
      return (
        <Card size="sm">
          <CardHeader>
            <CardDescription>{widget.label || "Status"}</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-1.5">
            <div>
              <Badge variant={variant}>
                <Icon />
                {word}
              </Badge>
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
        <Card size="sm">
          <CardHeader>
            <CardDescription>{widget.label || "Progress"}</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-2">
            <div className="flex items-baseline justify-between gap-3">
              <CardTitle className="font-heading text-2xl font-semibold tabular-nums">{unitless ? `${percent}%` : formatMetricValue(widget.value, widget.unit)}</CardTitle>
              <span className="text-sm text-muted-foreground tabular-nums">
                {formatMetricValue(widget.value, null)} / {formatMetricValue(widget.max, widget.unit)}
              </span>
            </div>
            <Progress value={percent} aria-label={widget.label || "Progress"} />
          </CardContent>
        </Card>
      );
    }
    case "list":
      return (
        <Card size="sm">
          <CardHeader>
            <CardDescription>{widget.title ?? "List"}</CardDescription>
          </CardHeader>
          <CardContent>
            {widget.items.length === 0 ? (
              <p className="text-sm text-muted-foreground">Nothing listed.</p>
            ) : (
              <ul className="flex flex-col gap-1.5 text-sm">
                {widget.items.map((item, i) => (
                  <li key={i} className="flex gap-2">
                    <span className="mt-[7px] size-1.5 shrink-0 rounded-full bg-foreground/40" aria-hidden="true" />
                    <span>{item}</span>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      );
    case "text":
      return (
        <Card size="sm">
          <CardHeader>
            <CardDescription>{widget.title ?? "Note"}</CardDescription>
          </CardHeader>
          <CardContent>
            <p className="text-sm whitespace-pre-line">{widget.body || <span className="text-muted-foreground">Empty.</span>}</p>
          </CardContent>
        </Card>
      );
    case "chart":
      return (
        <Card size="sm">
          <CardHeader>
            <CardDescription>{widget.label || "Chart"}</CardDescription>
          </CardHeader>
          <CardContent>
            {widget.points.length === 0 ? <p className="text-sm text-muted-foreground">No points.</p> : <Sparkline points={widget.points} unit={widget.unit} />}
          </CardContent>
        </Card>
      );
  }
}
