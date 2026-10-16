import { WidgetCard } from "@/components/Widgets";
import { HealthStrip } from "@/components/feed/HealthStrip";
import { rise } from "@/components/feed/styles";
import { bentoSpans, widgetBlocks } from "@/lib/feed-layout";
import type { Widget } from "@/lib/types";
import { widgetWide } from "@/lib/widgets";

// A dashboard as a bento, read-only, in the board's order: a run of
// statuses becomes one health strip across the top of its row, a chart
// takes two thirds of a row, a list or a note half, a number or a ring a
// third, and each row is filled to its edge (lib/feed-layout.ts
// bentoSpans): six columns on a wide screen, two on a tablet, one on a
// phone. Numbers count up and rings sweep in (components/Widgets.tsx).
// `compact` keeps to two columns, for the builder's preview beside its form.

// The widgets' cards, rounder and roomier than a small Card, like the rest
// of the feed's (the spacing replaces the small card's own).
const CARD_LOOK = "h-full rounded-[22px] ring-foreground/8 data-[size=sm]:[--card-spacing:--spacing(4.5)]";

// Static class names, so Tailwind sees every span it may need.
const SM_SPAN: Record<number, string> = { 1: "sm:col-span-1", 2: "sm:col-span-2" };
const LG_SPAN: Record<number, string> = {
  1: "lg:col-span-1",
  2: "lg:col-span-2",
  3: "lg:col-span-3",
  4: "lg:col-span-4",
  5: "lg:col-span-5",
  6: "lg:col-span-6",
};

export function DashboardBento({ widgets, compact = false }: { widgets: Widget[]; compact?: boolean }) {
  const blocks = widgetBlocks(widgets);
  const kinds = blocks.map((b) => (b.kind === "health" ? "health" : b.widget.type === "chart" ? "chart" : widgetWide(b.widget) ? "wide" : "small"));
  const sm = bentoSpans(kinds, 2);
  const lg = bentoSpans(kinds, 6);
  const place = (i: number) => `${SM_SPAN[sm[i]] ?? ""} ${compact ? "" : (LG_SPAN[lg[i]] ?? "")} rounded-[22px] ${rise(i).className}`;

  return (
    <div className={compact ? "grid grid-cols-1 gap-4 sm:grid-cols-2" : "grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-6"}>
      {blocks.map((block, i) =>
        block.kind === "health" ? (
          <div key={`health-${i}`} className={place(i)} style={rise(i).style}>
            <HealthStrip items={block.items} className={CARD_LOOK} />
          </div>
        ) : (
          <div key={`${block.index}-${block.widget.type}`} className={place(i)} style={rise(i).style}>
            <WidgetCard widget={block.widget} className={CARD_LOOK} />
          </div>
        ),
      )}
    </div>
  );
}
