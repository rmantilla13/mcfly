import {
  BotIcon,
  CalendarIcon,
  FileTextIcon,
  FolderKanbanIcon,
  GaugeIcon,
  LayoutDashboardIcon,
  MonitorIcon,
  NewspaperIcon,
  TrendingUpIcon,
  ZapIcon,
} from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
import { IngestTable } from "@/components/IngestTable";
import { PageHeader } from "@/components/PageHeader";
import { StatTile } from "@/components/StatTile";
import { EmptyState, Time } from "@/components/bits";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { getOverview, listDevices, listIngest, requireAdmin } from "@/lib/data";
import { formatDate, formatNumber, isOnline, plural } from "@/lib/format";

export const metadata: Metadata = { title: "Overview" };

export default async function OverviewPage() {
  await requireAdmin();
  const [o, pushes, devices] = await Promise.all([getOverview(), listIngest(1, 12), listDevices()]);

  return (
    <>
      <PageHeader eyebrow={formatDate(new Date().toISOString())} title="Overview" subtitle="What the agents pushed and what the displays are showing." />

      <div className="mb-5 grid grid-cols-5 gap-4 max-xl:grid-cols-3 max-md:grid-cols-2 max-sm:grid-cols-1">
        <StatTile
          label="Agents"
          value={formatNumber(o.agents)}
          href="/agents"
          icon={<BotIcon />}
          context={o.agents_revoked ? `${plural(o.agents_revoked, "agent")} revoked` : "All with a working key"}
        />
        <StatTile
          label="Pushes, last 24h"
          value={formatNumber(o.pushes_24h)}
          icon={<ZapIcon />}
          context={
            o.errors_24h ? `${plural(o.errors_24h, "push", "pushes")} refused` : o.last_push_at ? <>Last one <Time iso={o.last_push_at} /></> : "Nothing yet"
          }
          tone={o.errors_24h ? "warn" : undefined}
        />
        <StatTile
          label="Briefs"
          value={formatNumber(o.briefs)}
          href="/feed?tab=briefs"
          icon={<FileTextIcon />}
          context={`${formatNumber(o.briefs_24h)} in the last 24h`}
        />
        <StatTile
          label="Symbols"
          value={formatNumber(o.symbols)}
          href="/feed?tab=markets"
          icon={<TrendingUpIcon />}
          context={`${plural(o.quotes, "quote")} of history`}
        />
        <StatTile
          label="News reports"
          value={formatNumber(o.news_reports)}
          href="/feed?tab=news"
          icon={<NewspaperIcon />}
          context={o.latest_report ? `Latest: ${o.latest_report}` : "No report yet"}
        />
        <StatTile
          label="Projects"
          value={formatNumber(o.projects)}
          href="/feed?tab=projects"
          icon={<FolderKanbanIcon />}
          context={o.projects_blocked ? `${formatNumber(o.projects_blocked)} blocked` : "None blocked"}
          tone={o.projects_blocked ? "warn" : undefined}
        />
        <StatTile label="Metrics" value={formatNumber(o.metrics)} href="/feed?tab=metrics" icon={<GaugeIcon />} context="Shown on the display" />
        <StatTile label="Dashboards" value={formatNumber(o.dashboards)} href="/feed?tab=dashboards" icon={<LayoutDashboardIcon />} context="Shown on the display" />
        <StatTile label="Events" value={formatNumber(o.events_upcoming)} href="/feed?tab=calendar" icon={<CalendarIcon />} context="In the next 7 days" />
        <StatTile
          label="Displays"
          value={formatNumber(o.devices)}
          href="/displays"
          icon={<MonitorIcon />}
          context={`${formatNumber(o.devices_online)} online now`}
        />
      </div>

      <div className="grid grid-cols-[minmax(0,1.7fr)_minmax(0,1fr)] gap-5 max-xl:grid-cols-1">
        <Card className="py-0 gap-0">
          <CardHeader className="border-b py-4">
            <CardTitle>Recent pushes</CardTitle>
            <CardDescription>The newest entries in the ingest log.</CardDescription>
            <CardAction>
              <Button variant="outline" size="sm" asChild>
                <Link href="/agents">Agents</Link>
              </Button>
            </CardAction>
          </CardHeader>
          <CardContent className="px-0 pb-2">
            <IngestTable entries={pushes.rows} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Displays</CardTitle>
            <CardDescription>Paired screens and when they last checked in.</CardDescription>
            <CardAction>
              <Button variant="outline" size="sm" asChild>
                <Link href="/displays">Manage</Link>
              </Button>
            </CardAction>
          </CardHeader>
          <CardContent>
            {devices.length === 0 ? (
              <EmptyState title="No displays paired" icon={<MonitorIcon />}>
                Enter the code a display shows under Displays → Pair a display.
              </EmptyState>
            ) : (
              <ul className="flex flex-col">
                {devices.map((d, i) => (
                  <li key={d.id}>
                    {i > 0 ? <Separator className="my-3" /> : null}
                    <div className="flex items-center justify-between gap-3">
                      <div className="min-w-0">
                        <div className="truncate font-medium">{d.name}</div>
                        <div className="text-[13px] text-muted-foreground">
                          Last seen <Time iso={d.last_seen_at} />
                        </div>
                      </div>
                      {isOnline(d.last_seen_at) ? <Badge variant="success">Online</Badge> : <Badge variant="outline">Offline</Badge>}
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      </div>
    </>
  );
}
