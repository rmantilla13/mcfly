import { ChevronLeftIcon, Trash2Icon } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { deleteDashboardAction } from "@/app/(console)/actions";
import { ConfirmAction } from "@/components/ConfirmAction";
import { PageHeader } from "@/components/PageHeader";
import { WidgetCard } from "@/components/Widgets";
import { AgentLabel, Time } from "@/components/bits";
import { Alert, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { getDashboard, requireAdmin } from "@/lib/data";
import { plural } from "@/lib/format";
import { parseWidgets } from "@/lib/widgets";

type Props = { params: Promise<{ id: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const dashboard = await getDashboard((await params).id);
  return { title: dashboard ? `${dashboard.title} · Dashboards` : "Dashboard" };
}

// The dashboard as the display draws it, read-only: one card per widget in
// the agent's order.
export default async function DashboardPage({ params }: Props) {
  await requireAdmin();
  const dashboard = await getDashboard((await params).id);
  if (!dashboard) notFound();
  const widgets = parseWidgets(dashboard.widgets);
  const unreadable = dashboard.widgets.length - widgets.length;

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

      <div className="grid grid-cols-3 gap-4 max-lg:grid-cols-2 max-sm:grid-cols-1">
        {widgets.map((w, i) => (
          <WidgetCard key={i} widget={w} />
        ))}
      </div>
    </>
  );
}
