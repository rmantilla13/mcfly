import { PlusIcon } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
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
import { BriefsFeed } from "@/components/BriefsFeed";
import { BriefsTable } from "@/components/BriefsTable";
import { CalendarList } from "@/components/CalendarList";
import { DashboardsTable } from "@/components/DashboardsTable";
import { FeedTabs } from "@/components/FeedTabs";
import { MarketsGrid } from "@/components/MarketsGrid";
import { MetricsGrid } from "@/components/MetricsGrid";
import { MetricsTable } from "@/components/MetricsTable";
import { NewsReportsTable } from "@/components/NewsReportsTable";
import { PageHeader } from "@/components/PageHeader";
import { ProjectsBoard } from "@/components/ProjectsBoard";
import { ProjectsTable } from "@/components/ProjectsTable";
import { QuotesTable } from "@/components/QuotesTable";
import { Pagination, pageHref, readPage, readString } from "@/components/bits";
import { FeedHeader } from "@/components/feed/bits";
import { NewsReportCards } from "@/components/feed/NewsReportCards";
import { ViewSwitch } from "@/components/feed/ViewSwitch";
import { Alert, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  getSettings,
  listBriefs,
  listDashboards,
  listEvents,
  listMetrics,
  listNewsReports,
  listProjects,
  listQuotes,
  listSeries,
  requireAdmin,
} from "@/lib/data";
import { safeTimeZone } from "@/lib/events";
import { type FeedTab, readFeedTab } from "@/lib/feed-tabs";
import { plural } from "@/lib/format";
import type { SeriesPoint } from "@/lib/series";
import type { MetricRow, QuoteRow } from "@/lib/types";

export const metadata: Metadata = { title: "Feed" };

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

const DELETED: Record<string, string> = { "1": "Report deleted.", project: "Project deleted.", dashboard: "Dashboard deleted." };

// The feeds' month of history for the cards' lines. A failed read costs the
// lines, not the page.
const SERIES_DAYS = 30;
async function history(kind: "quotes" | "metrics", keys: string[]): Promise<Record<string, SeriesPoint[]>> {
  if (keys.length === 0) return {};
  try {
    return await listSeries(kind, keys, SERIES_DAYS);
  } catch (error) {
    console.error(`${kind} history for the feed failed:`, error);
    return {};
  }
}

// The shown symbols' and metrics' month, and the time it was read at (the
// briefs' expiry bars run against it).
async function histories(quotes: QuoteRow[], metrics: MetricRow[]) {
  const [q, m] = await Promise.all([
    history("quotes", quotes.filter((x) => !x.hidden && x.price != null).map((x) => x.symbol)),
    history("metrics", metrics.filter((x) => !x.hidden && x.value != null).map((x) => x.key)),
  ]);
  return { quotes: q, metrics: m, now: Date.now() };
}

// One flush card per tab: a header line, then the table. The tabs that have
// cards keep their table here, under Manage.
function Section({ title, description, action, children }: { title: string; description: ReactNode; action?: ReactNode; children: ReactNode }) {
  return (
    <Card className="gap-0 py-0">
      <CardHeader className="border-b py-4">
        <CardTitle>{title}</CardTitle>
        <CardDescription>{description}</CardDescription>
        {action ? <CardAction>{action}</CardAction> : null}
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
  const { quotes: quoteHistory, metrics: metricHistory, now } = await histories(quotes, metrics);
  // Manage (the tables) or cards, for the tab the page opened on; the others
  // open on their cards.
  const manage = readString(sp.view) === "manage";
  const viewOf = (t: FeedTab) => (manage && t === tab ? "manage" : "cards");

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
              <ViewSwitch
                initial={viewOf("briefs")}
                header={<FeedHeader title="Briefs" description="A day at a time, newest first. Expired briefs are pruned by the ingest function after a day." />}
                cards={
                  <>
                    <BriefsFeed briefs={briefs.rows} timeZone={timeZone} now={now} />
                    <Pagination page={briefs.page} hasMore={briefs.hasMore} shown={briefs.rows.length} href={pageHref("/feed", { tab: "briefs" })} />
                  </>
                }
                manage={
                  <Section title="Briefs" description="Newest first. Expired briefs are pruned by the ingest function after a day.">
                    <BriefsTable briefs={briefs.rows} deleteAction={deleteBriefAction} />
                    <Pagination page={briefs.page} hasMore={briefs.hasMore} shown={briefs.rows.length} href={pageHref("/feed", { tab: "briefs", view: "manage" })} />
                  </Section>
                }
              />
            ),
          },
          {
            value: "markets",
            label: "Markets",
            count: quotes.length,
            content: (
              <ViewSwitch
                initial={viewOf("markets")}
                header={<FeedHeader title="Markets" description={<>{plural(quotes.length, "symbol")}, in the display&apos;s order · the last 30 days</>} />}
                cards={<MarketsGrid quotes={quotes} series={quoteHistory} timeZone={timeZone} />}
                manage={
                  <Section title="Markets" description={<>{plural(quotes.length, "symbol")} · the display lists the ones that aren&apos;t hidden, by order then symbol.</>}>
                    <QuotesTable quotes={quotes} setAction={setSymbolAction} deleteAction={deleteSymbolAction} />
                  </Section>
                }
              />
            ),
          },
          {
            value: "news",
            label: "News",
            count: reports.length,
            content: (
              <ViewSwitch
                initial={viewOf("news")}
                header={<FeedHeader title="News" description="Daily Pulse reports, newest first. Open one to read its stories." />}
                cards={<NewsReportCards reports={reports} />}
                manage={
                  <Section title="News" description="Daily Pulse reports, newest first. Open one to read its stories.">
                    <NewsReportsTable reports={reports} deleteAction={deleteNewsReportAction} />
                  </Section>
                }
              />
            ),
          },
          {
            value: "projects",
            label: "Projects",
            count: projects.length,
            content: (
              <ViewSwitch
                initial={viewOf("projects")}
                header={<FeedHeader title="Projects" description="What the agents report work on, by status. Open one for its history." />}
                cards={<ProjectsBoard projects={projects} />}
                manage={
                  <Section title="Projects" description="What the agents report work on, done ones last. Open one for its history.">
                    <ProjectsTable projects={projects} deleteAction={deleteProjectAction} />
                  </Section>
                }
              />
            ),
          },
          {
            value: "metrics",
            label: "Metrics",
            count: metrics.length,
            content: (
              <ViewSwitch
                initial={viewOf("metrics")}
                header={<FeedHeader title="Metrics" description={<>{plural(metrics.length, "metric")} by group, in the display&apos;s order · green is good news</>} />}
                cards={<MetricsGrid metrics={metrics} series={metricHistory} />}
                manage={
                  <Section title="Metrics" description={<>{plural(metrics.length, "metric")} by group · the display shows the ones that aren&apos;t hidden, in order.</>}>
                    <MetricsTable metrics={metrics} setAction={setMetricAction} deleteAction={deleteMetricAction} />
                  </Section>
                }
              />
            ),
          },
          {
            value: "dashboards",
            label: "Dashboards",
            count: dashboards.length,
            content: (
              <Section
                title="Dashboards"
                description="Made here from a template, or laid out by an agent. Open one to see it as the display draws it."
                action={
                  <Button asChild size="sm">
                    <Link href="/feed/dashboards/new">
                      <PlusIcon data-icon="inline-start" />
                      New dashboard
                    </Link>
                  </Button>
                }
              >
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
