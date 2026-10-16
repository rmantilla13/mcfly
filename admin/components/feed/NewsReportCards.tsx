import { cn } from "cn";
import { NewspaperIcon } from "lucide-react";
import Link from "next/link";
import { AgentLabel, EmptyState, Time } from "@/components/bits";
import { CARD, LIFT, rise, STRETCH } from "@/components/feed/styles";
import { Badge } from "@/components/ui/badge";
import { sectionColorByName } from "@/lib/feed-layout";
import { formatShortDate, plural } from "@/lib/format";
import type { NewsReportRow } from "@/lib/types";

// The News tab as a card per Daily Pulse report, newest first: the day, its
// sections in the colours the display gives them (a band of them along the
// top), how many stories, and who sent it. A card opens the report.

const WEEKDAY = new Intl.DateTimeFormat("en-US", { weekday: "long", timeZone: "UTC" });

export function NewsReportCards({ reports }: { reports: NewsReportRow[] }) {
  if (reports.length === 0) {
    return (
      <EmptyState title="No reports" icon={<NewspaperIcon />}>
        Daily Pulse reports an agent pushes (POST /ingest/news) show up here, newest first.
      </EmptyState>
    );
  }
  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {reports.map((report, i) => {
        const colors = report.sections.map((name, j) => sectionColorByName(name, j));
        const band = colors.length > 1 ? `linear-gradient(90deg in oklab, ${colors.join(", ")})` : (colors[0] ?? "var(--primary)");
        const day = Date.parse(`${report.report_date}T12:00:00Z`);
        const r = rise(i);
        return (
          <article key={report.id} className={cn(CARD, LIFT, "relative flex flex-col gap-4 overflow-hidden p-5 pt-6", r.className)} style={r.style}>
            <span aria-hidden="true" className="absolute inset-x-0 top-0 h-1.5" style={{ background: band }} />
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                {Number.isFinite(day) ? <div className="text-xs font-semibold tracking-wider text-muted-foreground uppercase">{WEEKDAY.format(day)}</div> : null}
                <h3 className="mt-1 font-heading text-2xl leading-tight font-semibold tracking-tight">
                  <Link href={`/feed/news/${report.id}`} className={cn(STRETCH, "text-foreground no-underline")}>
                    {report.display_date ?? formatShortDate(report.report_date)}
                  </Link>
                </h3>
              </div>
              {i === 0 ? <Badge>Latest</Badge> : null}
            </div>
            {report.sections.length ? (
              <ul className="flex flex-wrap gap-1.5" aria-label="Sections">
                {report.sections.map((name, j) => (
                  <li key={name} className="inline-flex h-6 items-center gap-1.5 rounded-full bg-foreground/5 px-2.5 text-xs font-medium">
                    <span className="size-2 rounded-full" style={{ background: colors[j] }} aria-hidden="true" />
                    {name}
                  </li>
                ))}
              </ul>
            ) : null}
            <div className="mt-auto flex flex-wrap items-center justify-between gap-x-3 gap-y-1 border-t border-foreground/8 pt-3 text-[13px] text-muted-foreground">
              <span className="inline-flex items-center gap-1.5">
                <NewspaperIcon className="size-3.5" aria-hidden="true" />
                {plural(report.item_count, "story", "stories")}
              </span>
              <span className="inline-flex items-center gap-2">
                <AgentLabel name={report.agent_name} color={report.agent_color} />
                <span aria-hidden="true">·</span>
                <Time iso={report.published_at} />
              </span>
            </div>
          </article>
        );
      })}
    </div>
  );
}
