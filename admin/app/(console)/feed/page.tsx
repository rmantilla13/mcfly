import type { Metadata } from "next";
import type { ReactNode } from "react";
import {
  deleteBriefAction,
  deleteCalendarAction,
  deleteDashboardAction,
  deleteEventAction,
  deleteMetricAction,
  deleteNewsReportAction,
  deleteProjectAction,
  deleteSymbolAction,
  setDashboardAction,
  setMetricAction,
  setSymbolAction,
} from "@/app/(console)/actions";
import { BriefsTable } from "@/components/BriefsTable";
import { CalendarList } from "@/components/CalendarList";
import { DashboardsTable } from "@/components/DashboardsTable";
import { FeedTabs } from "@/components/FeedTabs";
import { MetricsTable } from "@/components/MetricsTable";
import { NewsReportsTable } from "@/components/NewsReportsTable";
import { PageHeader } from "@/components/PageHeader";
import { ProjectsTable } from "@/components/ProjectsTable";
import { QuotesTable } from "@/components/QuotesTable";
import { Pagination, pageHref, readPage, readString } from "@/components/bits";
import { Alert, AlertTitle } from "@/components/ui/alert";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  getSettings,
  listBriefs,
  listDashboards,
  listEvents,
  listMetrics,
  listNewsReports,
  listProjects,
  listQuotes,
  requireAdmin,
} from "@/lib/data";
import { safeTimeZone } from "@/lib/events";
import { readFeedTab } from "@/lib/feed-tabs";
import { plural } from "@/lib/format";

export const metadata: Metadata = { title: "Feed" };

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

const DELETED: Record<string, string> = { "1": "Report deleted.", project: "Project deleted.", dashboard: "Dashboard deleted." };

// One flush card per tab: a header line, then the table.
function Section({ title, description, children }: { title: string; description: ReactNode; children: ReactNode }) {
  return (
    <Card className="gap-0 py-0">
      <CardHeader className="border-b py-4">
        <CardTitle>{title}</CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>
      <CardContent className="px-0 pt-2 pb-2">{children}</CardContent>
    </Card>
  );
}

export default async function FeedPage({ searchParams }: Props) {
  await requireAdmin();
  const sp = await searchParams;
  const tab = readFeedTab(sp.tab);
  const page = readPage(sp.page);
  const [briefs, quotes, reports, projects, metrics, dashboards, events, settings] = await Promise.all([
    listBriefs(page),
    listQuotes(),
    listNewsReports(),
    listProjects(),
    listMetrics(),
    listDashboards(),
    listEvents(7, 60),
    getSettings(),
  ]);
  const timeZone = safeTimeZone(settings.timezone);
  const deleted = DELETED[readString(sp.deleted)];

  return (
    <>
      <PageHeader title="Feed" subtitle="Everything the displays show, one tab per feed." />
      {deleted ? (
        <Alert className="mb-4">
          <AlertTitle>{deleted}</AlertTitle>
        </Alert>
      ) : null}
      <FeedTabs
        initial={tab}
        tabs={[
          {
            value: "briefs",
            label: "Briefs",
            count: briefs.rows.length,
            content: (
              <Section title="Briefs" description="Newest first. Expired briefs are pruned by the ingest function after a day.">
                <BriefsTable briefs={briefs.rows} deleteAction={deleteBriefAction} />
                <Pagination page={briefs.page} hasMore={briefs.hasMore} shown={briefs.rows.length} href={pageHref("/feed", { tab: "briefs" })} />
              </Section>
            ),
          },
          {
            value: "markets",
            label: "Markets",
            count: quotes.length,
            content: (
              <Section title="Markets" description={<>{plural(quotes.length, "symbol")} · the display lists the ones that aren&apos;t hidden, by order then symbol.</>}>
                <QuotesTable quotes={quotes} setAction={setSymbolAction} deleteAction={deleteSymbolAction} />
              </Section>
            ),
          },
          {
            value: "news",
            label: "News",
            count: reports.length,
            content: (
              <Section title="News" description="Daily Pulse reports, newest first. Open one to read its stories.">
                <NewsReportsTable reports={reports} deleteAction={deleteNewsReportAction} />
              </Section>
            ),
          },
          {
            value: "projects",
            label: "Projects",
            count: projects.length,
            content: (
              <Section title="Projects" description="What the agents report work on, done ones last. Open one for its history.">
                <ProjectsTable projects={projects} deleteAction={deleteProjectAction} />
              </Section>
            ),
          },
          {
            value: "metrics",
            label: "Metrics",
            count: metrics.length,
            content: (
              <Section title="Metrics" description={<>{plural(metrics.length, "metric")} by group · the display shows the ones that aren&apos;t hidden, in order.</>}>
                <MetricsTable metrics={metrics} setAction={setMetricAction} deleteAction={deleteMetricAction} />
              </Section>
            ),
          },
          {
            value: "dashboards",
            label: "Dashboards",
            count: dashboards.length,
            content: (
              <Section title="Dashboards" description="Laid out by the agents. Open one to see its widgets as the display draws them.">
                <DashboardsTable dashboards={dashboards} setAction={setDashboardAction} deleteAction={deleteDashboardAction} />
              </Section>
            ),
          },
          {
            value: "calendar",
            label: "Calendar",
            count: events.length,
            content: (
              <Section title="Calendar" description={<>A week back and two months ahead, in {timeZone} (Settings → Time zone).</>}>
                <CalendarList events={events} timeZone={timeZone} deleteEventAction={deleteEventAction} deleteCalendarAction={deleteCalendarAction} />
              </Section>
            ),
          },
        ]}
      />
    </>
  );
}
