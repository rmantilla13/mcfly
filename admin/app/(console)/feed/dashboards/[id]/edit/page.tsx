import { ChevronLeftIcon } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { previewDashboardAction, saveDashboardAction } from "@/app/(console)/actions";
import { PageHeader } from "@/components/PageHeader";
import { DashboardBuilder } from "@/components/dashboards/DashboardBuilder";
import { getDashboard, getDashboardSourceOptions, requireAdmin } from "@/lib/data";
import { readParts } from "@/lib/dashboard-sources";

type Props = { params: Promise<{ id: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const dashboard = await getDashboard((await params).id);
  return { title: dashboard ? `Edit ${dashboard.title} · Dashboards` : "Dashboard" };
}

// A made board's recipe, open in the builder. An agent's board has none:
// the agent lays it out, so it goes back to its page.
export default async function EditDashboardPage({ params }: Props) {
  await requireAdmin();
  const { id } = await params;
  const [dashboard, options] = await Promise.all([getDashboard(id), getDashboardSourceOptions()]);
  if (!dashboard) notFound();
  if (!dashboard.sources) redirect(`/feed/dashboards/${dashboard.id}`);
  return (
    <>
      <PageHeader
        eyebrow={
          <Link href={`/feed/dashboards/${dashboard.id}`} className="inline-flex items-center gap-1 text-muted-foreground no-underline hover:text-foreground">
            <ChevronLeftIcon className="size-3.5" /> {dashboard.title}
          </Link>
        }
        title={`Edit ${dashboard.title}`}
        subtitle="Change what each part pulls from. Saving redraws it on every display."
      />
      <DashboardBuilder
        options={options}
        saveAction={saveDashboardAction}
        previewAction={previewDashboardAction}
        initial={{
          id: dashboard.id,
          title: dashboard.title,
          subtitle: dashboard.subtitle,
          template: dashboard.template,
          parts: readParts(dashboard.sources),
          widgets: dashboard.widgets,
        }}
      />
    </>
  );
}
