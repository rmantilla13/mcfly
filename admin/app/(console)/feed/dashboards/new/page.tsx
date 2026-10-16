import { ChevronLeftIcon } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
import { previewDashboardAction, saveDashboardAction } from "@/app/(console)/actions";
import { PageHeader } from "@/components/PageHeader";
import { DashboardBuilder } from "@/components/dashboards/DashboardBuilder";
import { getDashboardSourceOptions, requireAdmin } from "@/lib/data";

export const metadata: Metadata = { title: "New dashboard" };

// A dashboard made here: a template to start from, and where each part
// pulls from. The database draws it and keeps it drawn on every display.
export default async function NewDashboardPage() {
  await requireAdmin();
  const options = await getDashboardSourceOptions();
  return (
    <>
      <PageHeader
        eyebrow={
          <Link href="/feed?tab=dashboards" className="inline-flex items-center gap-1 text-muted-foreground no-underline hover:text-foreground">
            <ChevronLeftIcon className="size-3.5" /> Dashboards
          </Link>
        }
        title="New dashboard"
        subtitle="Pick a template, then choose what each part pulls from. The display shows it as soon as you create it."
      />
      <DashboardBuilder options={options} saveAction={saveDashboardAction} previewAction={previewDashboardAction} />
    </>
  );
}
