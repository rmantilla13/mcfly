import { cn } from "cn";
import {
  CalendarIcon,
  FileTextIcon,
  FolderKanbanIcon,
  GaugeIcon,
  LayoutDashboardIcon,
  MonitorIcon,
  NewspaperIcon,
  TrendingUpIcon,
} from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";
import { AgentsRoster } from "@/components/AgentsRoster";
import { AnimatedNumber } from "@/components/AnimatedNumber";
import { IngestTable } from "@/components/IngestTable";
import { PageHeader } from "@/components/PageHeader";
import { EmptyState, Time } from "@/components/bits";
import { RingGauge, StatusDot } from "@/components/charts";
import { PushesCard } from "@/components/feed/PushesCard";
import { CARD, LIFT, rise, STRETCH } from "@/components/feed/styles";
import { Button } from "@/components/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { getOverview, getSettings, listAgents, listDevices, listIngest, listIngestSince, requireAdmin } from "@/lib/data";
import { safeTimeZone } from "@/lib/events";
import { formatDate, formatNumber, formatShortDate, isOnline, plural } from "@/lib/format";
import type { IngestEntry } from "@/lib/types";

export const metadata: Metadata = { title: "Overview" };

// The console's front page: the day's pushes as the hero, the displays as a
// ring, every agent's heartbeat, the rest of the counts as a row of chips,
// then the newest entries in the push log.
export default async function OverviewPage() {
  await requireAdmin();
  const { o, pushes, devices, agents, settings, day, now } = await load();
  const timeZone = safeTimeZone(settings.timezone);
  const online = devices.filter((d) => isOnline(d.last_seen_at, now)).length;

  return (
    <>
      <PageHeader eyebrow={formatDate(new Date(now).toISOString())} title="Overview" subtitle="What the agents pushed and what the displays are showing." />

      <div className="flex flex-col gap-5">
        <div className="grid grid-cols-1 gap-5 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]">
          <PushesCard
            total={o.pushes_24h}
            refused={o.errors_24h}
            lastPushAt={o.last_push_at}
            entries={day}
            now={now}
            timeZone={timeZone}
            className={rise(0).className}
          />
          <DisplaysCard devices={devices} online={online} now={now} />
        </div>

        <ul className="grid grid-cols-2 gap-3 sm:grid-cols-4 xl:grid-cols-7" aria-label="Feeds">
          <CountChip index={0} label="Briefs" value={o.briefs} href="/feed?tab=briefs" icon={<FileTextIcon />} context={`${formatNumber(o.briefs_24h)} today`} />
          <CountChip index={1} label="Symbols" value={o.symbols} href="/feed?tab=markets" icon={<TrendingUpIcon />} context={`${formatNumber(o.quotes)} quotes`} />
          <CountChip index={2} label="News" value={o.news_reports} href="/feed?tab=news" icon={<NewspaperIcon />} context={o.latest_report ? `Latest ${/^\d{4}-\d{2}-\d{2}$/.test(o.latest_report) ? formatShortDate(o.latest_report) : o.latest_report}` : "No report yet"} />
          <CountChip
            index={3}
            label="Projects"
            value={o.projects}
            href="/feed?tab=projects"
            icon={<FolderKanbanIcon />}
            context={o.projects_blocked ? `${formatNumber(o.projects_blocked)} blocked` : "None blocked"}
            warn={o.projects_blocked > 0}
          />
          <CountChip index={4} label="Metrics" value={o.metrics} href="/feed?tab=metrics" icon={<GaugeIcon />} context="On the display" />
          <CountChip index={5} label="Dashboards" value={o.dashboards} href="/feed?tab=dashboards" icon={<LayoutDashboardIcon />} context="On the display" />
          <CountChip index={6} label="Events" value={o.events_upcoming} href="/feed?tab=calendar" icon={<CalendarIcon />} context="Next 7 days" />
        </ul>

        <section className={cn(CARD, "flex flex-col gap-4 p-6 max-sm:p-5", rise(2).className)} style={rise(2).style} aria-labelledby="agents-title">
          <div className="flex flex-wrap items-end justify-between gap-3">
            <div>
              <h2 id="agents-title" className="font-heading text-base font-semibold">
                Agents
              </h2>
              <p className="mt-0.5 text-[13px] text-muted-foreground">
                {plural(o.agents, "agent")} with a working key{o.agents_revoked ? `, ${formatNumber(o.agents_revoked)} revoked` : ""} · a breathing dot is pushing on its usual rhythm
              </p>
            </div>
            <Button variant="outline" size="sm" asChild>
              <Link href="/agents">Manage</Link>
            </Button>
          </div>
          <AgentsRoster agents={agents} pushes={day} now={now} />
        </section>

        <Card className="gap-0 rounded-[24px] py-0 ring-foreground/8">
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
      </div>
    </>
  );
}

// Everything the page shows, read at once, and the time it was read at
// (the agents' heartbeat and the hourly bars are measured against it).
async function load() {
  const [o, pushes, devices, agents, settings, day] = await Promise.all([
    getOverview(),
    listIngest(1, 12),
    listDevices(),
    listAgents(),
    getSettings(),
    // The bars and the agents' rhythm. A failed read costs the bars, not the page.
    listIngestSince(24).catch((error: unknown): IngestEntry[] => {
      console.error("push log for the overview failed:", error);
      return [];
    }),
  ]);
  return { o, pushes, devices, agents, settings, day, now: Date.now() };
}

// The paired displays: how many are online as a ring, then each with its
// state and when it last checked in.
function DisplaysCard({ devices, online, now }: { devices: Awaited<ReturnType<typeof listDevices>>; online: number; now: number }) {
  const r = rise(1);
  return (
    <section className={cn(CARD, "flex flex-col gap-5 p-6 max-sm:p-5", r.className)} style={r.style} aria-labelledby="displays-title">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h2 id="displays-title" className="flex items-center gap-2 text-sm font-medium text-muted-foreground">
            <span className="grid size-7 place-items-center rounded-lg bg-accent text-accent-foreground" aria-hidden="true">
              <MonitorIcon className="size-4" />
            </span>
            Displays
          </h2>
        </div>
        <Button variant="outline" size="sm" asChild>
          <Link href="/displays">Manage</Link>
        </Button>
      </div>
      {devices.length === 0 ? (
        <EmptyState title="No displays paired" icon={<MonitorIcon />}>
          Enter the code a display shows under Displays → Pair a display.
        </EmptyState>
      ) : (
        <>
          <div className="flex items-center gap-5">
            <RingGauge value={online / devices.length} size={112} stroke={10} tone="up" label={`${online} of ${devices.length} displays online`}>
              <span className="font-heading text-[26px] font-semibold tracking-tight tabular-nums">
                <AnimatedNumber value={online} format="int" />
                <span className="text-muted-foreground">/{devices.length}</span>
              </span>
              <span className="mt-1 text-[11px] font-medium text-muted-foreground">online</span>
            </RingGauge>
            <p className="text-[13px] text-muted-foreground">
              {online === devices.length ? "Every display has checked in within 15 minutes." : `${plural(devices.length - online, "display")} quiet for over 15 minutes.`}
            </p>
          </div>
          <ul className="flex flex-col gap-3 border-t border-foreground/8 pt-4">
            {devices.map((d) => {
              const up = isOnline(d.last_seen_at, now);
              return (
                <li key={d.id} className="flex items-center gap-3">
                  <StatusDot state={up ? "ok" : "unknown"} label={up ? "Online" : "Offline"} />
                  <span className="min-w-0 flex-1 truncate font-medium">{d.name}</span>
                  <span className="text-[13px] text-muted-foreground">{up ? "Online" : <Time iso={d.last_seen_at} />}</span>
                </li>
              );
            })}
          </ul>
        </>
      )}
    </section>
  );
}

// One of the smaller counts: a chip that opens its tab.
function CountChip({
  index,
  label,
  value,
  href,
  icon,
  context,
  warn,
}: {
  index: number;
  label: string;
  value: number;
  href: string;
  icon: ReactNode;
  context: string;
  warn?: boolean;
}) {
  const r = rise(index + 3);
  return (
    // The seventh fills out its row when the row is two or four wide.
    <li className={cn(CARD, LIFT, "relative flex flex-col gap-1.5 rounded-[20px] px-4 py-3.5 last:col-span-2 xl:last:col-span-1", r.className)} style={r.style}>
      <span className="flex items-center justify-between gap-2 text-[13px] font-medium text-muted-foreground">
        <Link href={href} className={cn(STRETCH, "text-inherit no-underline")}>
          {label}
        </Link>
        <span className={cn("[&_svg]:size-4", warn ? "text-warning" : "text-muted-foreground/70")} aria-hidden="true">
          {icon}
        </span>
      </span>
      <span className="font-heading text-2xl leading-none font-semibold tracking-tight">
        <AnimatedNumber value={value} format="int" />
      </span>
      <span className={cn("truncate text-xs", warn ? "font-medium text-warning" : "text-muted-foreground")}>{context}</span>
    </li>
  );
}
