import { ChevronLeftIcon, Trash2Icon } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { deleteDashboardAction } from "@/app/(console)/actions";
import { ConfirmAction } from "@/components/ConfirmAction";
import { PageHeader } from "@/components/PageHeader";
import { WidgetCard } from "@/components/Widgets";
import { AgentLabel, Time } from "@/components/bits";
import { HealthStrip } from "@/components/feed/HealthStrip";
import { rise } from "@/components/feed/styles";
import { Alert, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { getDashboard, requireAdmin } from "@/lib/data";
import { bentoSpans, widgetBlocks } from "@/lib/feed-layout";
import { plural } from "@/lib/format";
import { parseWidgets, widgetWide } from "@/lib/widgets";

type Props = { params: Promise<{ id: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const dashboard = await getDashboard((await params).id);
  return { title: dashboard ? `${dashboard.title} · Dashboards` : "Dashboard" };
}

// The dashboard as a bento, read-only, in the agent's order: a run of
// statuses becomes one health strip across the top of its row, a chart
// takes two thirds of a row, a list or a note half, a number or a ring a
// third, and each row is filled to its edge (lib/feed-layout.ts
// bentoSpans): six columns on a wide screen, two on a tablet, one on a
// phone. Numbers count up and rings sweep in (components/Widgets.tsx).

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
export default async function DashboardPage({ params }: Props) {
  await requireAdmin();
  const dashboard = await getDashboard((await params).id);
  if (!dashboard) notFound();
  const widgets = parseWidgets(dashboard.widgets);
  const unreadable = dashboard.widgets.length - widgets.length;
  const blocks = widgetBlocks(widgets);
  const kinds = blocks.map((b) => (b.kind === "health" ? "health" : b.widget.type === "chart" ? "chart" : widgetWide(b.widget) ? "wide" : "small"));
  const sm = bentoSpans(kinds, 2);
  const lg = bentoSpans(kinds, 6);
  const place = (i: number) => `${SM_SPAN[sm[i]] ?? ""} ${LG_SPAN[lg[i]] ?? ""} rounded-[22px] ${rise(i).className}`;

  return (
    <>
      <PageHeader
        eyebrow={
          <Link href="/feed?tab=dashboards" className="inline-flex items-center gap-1 text-muted-foreground no-underline hover:text-foreground">
            <ChevronLeftIcon className="size-3.5" /> Dashboards
          </Link>
        }
        title={
          <span className="inline-flex flex-wrap items-center gap-3">
            {dashboard.title}
            {dashboard.hidden ? <Badge variant="warning">Hidden</Badge> : null}
          </span>
        }
        subtitle={
          <span className="inline-flex flex-wrap items-center gap-x-3 gap-y-1">
            {dashboard.subtitle ? <span>{dashboard.subtitle}</span> : null}
            <AgentLabel name={dashboard.agent_name} color={dashboard.agent_color} />
            <span>
              key <code className="font-mono">{dashboard.key}</code>
            </span>
            <span>
              {plural(widgets.length, "widget")} · updated <Time iso={dashboard.updated_at} />
            </span>
          </span>
        }
        actions={
          <ConfirmAction
            action={deleteDashboardAction}
            fields={{ dashboard_id: dashboard.id }}
            title={`Delete ${dashboard.title}?`}
            description="The dashboard leaves every display. The agent's next push brings it back."
            confirmLabel="Delete dashboard"
            tone="danger"
            trigger={
              <Button variant="destructive">
                <Trash2Icon data-icon="inline-start" />
                Delete dashboard
              </Button>
            }
          />
        }
      />

      {unreadable > 0 ? (
        <Alert className="mb-4">
          <AlertTitle>
            {plural(unreadable, "widget")} could not be read and {unreadable === 1 ? "is" : "are"} not shown.
          </AlertTitle>
        </Alert>
      ) : null}

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-6">
        {blocks.map((block, i) =>
          block.kind === "health" ? (
            <div key={`health-${i}`} className={place(i)} style={rise(i).style}>
              <HealthStrip items={block.items} className={CARD_LOOK} />
            </div>
          ) : (
            <div key={block.index} className={place(i)} style={rise(i).style}>
              <WidgetCard widget={block.widget} className={CARD_LOOK} />
            </div>
          ),
        )}
      </div>
    </>
  );
}
