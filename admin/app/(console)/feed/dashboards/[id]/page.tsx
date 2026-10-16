import { ChevronLeftIcon, PencilIcon, Trash2Icon } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { deleteDashboardAction } from "@/app/(console)/actions";
import { ConfirmAction } from "@/components/ConfirmAction";
import { PageHeader } from "@/components/PageHeader";
import { AgentLabel, Time } from "@/components/bits";
import { DashboardBento } from "@/components/dashboards/DashboardBento";
import { Alert, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { describePart, findTemplate, partKind, readParts } from "@/lib/dashboard-sources";
import { getDashboard, getDashboardSourceOptions, requireAdmin } from "@/lib/data";
import { plural } from "@/lib/format";
import { parseWidgets } from "@/lib/widgets";

type Props = { params: Promise<{ id: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const dashboard = await getDashboard((await params).id);
  return { title: dashboard ? `${dashboard.title} · Dashboards` : "Dashboard" };
}

// The dashboard as the display draws it (components/dashboards/DashboardBento).
// A board made here also says what each part pulls from, and opens in the
// builder; an agent's board is the agent's to lay out.
export default async function DashboardPage({ params }: Props) {
  await requireAdmin();
  const dashboard = await getDashboard((await params).id);
  if (!dashboard) notFound();
  const widgets = parseWidgets(dashboard.widgets);
  const unreadable = dashboard.widgets.length - widgets.length;
  const made = dashboard.sources !== null;
  const parts = made ? readParts(dashboard.sources) : [];
  const options = made ? await getDashboardSourceOptions() : undefined;
  const template = findTemplate(dashboard.template);

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
            {made ? <span>Made here{template ? ` from ${template.label}` : ""}</span> : <AgentLabel name={dashboard.agent_name} color={dashboard.agent_color} />}
            <span>
              key <code className="font-mono">{dashboard.key}</code>
            </span>
            <span>
              {plural(widgets.length, "widget")} · {made ? "drawn" : "updated"} <Time iso={dashboard.updated_at} />
            </span>
          </span>
        }
        actions={
          <div className="flex flex-wrap gap-2">
            {made ? (
              <Button asChild variant="outline">
                <Link href={`/feed/dashboards/${dashboard.id}/edit`}>
                  <PencilIcon data-icon="inline-start" />
                  Edit
                </Link>
              </Button>
            ) : null}
            <ConfirmAction
              action={deleteDashboardAction}
              fields={{ dashboard_id: dashboard.id }}
              title={`Delete ${dashboard.title}?`}
              description={made ? "The dashboard leaves every display, and what it pulls from is forgotten." : "The dashboard leaves every display. The agent's next push brings it back."}
              confirmLabel="Delete dashboard"
              tone="danger"
              trigger={
                <Button variant="destructive">
                  <Trash2Icon data-icon="inline-start" />
                  Delete dashboard
                </Button>
              }
            />
          </div>
        }
      />

      {made && parts.length ? (
        <section className="mb-5 flex flex-wrap gap-2" aria-label="Where it pulls from">
          {parts.map((part, i) => (
            <span key={i} className="inline-flex items-center gap-2 rounded-full border bg-card px-3 py-1 text-xs">
              <span className="size-2 rounded-full" style={{ background: partKind(part.from).color }} aria-hidden="true" />
              <span className="font-medium">{partKind(part.from).label}</span>
              <span className="text-muted-foreground">{describePart(part, options)}</span>
            </span>
          ))}
        </section>
      ) : null}

      {unreadable > 0 ? (
        <Alert className="mb-4">
          <AlertTitle>
            {plural(unreadable, "widget")} could not be read and {unreadable === 1 ? "is" : "are"} not shown.
          </AlertTitle>
        </Alert>
      ) : null}

      <DashboardBento widgets={widgets} />
    </>
  );
}
