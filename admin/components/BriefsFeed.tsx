import { cn } from "cn";
import { CircleAlertIcon, FileTextIcon } from "lucide-react";
import type { CSSProperties } from "react";
import { AgentLabel, EmptyState, Swatch } from "@/components/bits";
import { AskLink } from "@/components/feed/bits";
import { CARD, rise } from "@/components/feed/styles";
import { Progress } from "@/components/ui/progress";
import { briefParts, expiryLeft, groupByDay } from "@/lib/feed-layout";
import { cssColor, formatDateTime, plural, preview } from "@/lib/format";
import { durationLabel } from "@/lib/insights";
import type { Brief } from "@/lib/types";

// The Briefs tab as a feed, a day at a time, newest first. Each kind reads
// the way it's meant: a daily brief is a card under a strip in its agent's
// colour with its points as bullets; an alert is marked in red with the
// time it has left as a bar running down; an hourly check-in is one line;
// anything else is a plain card.

const CLOCKS = new Map<string, Intl.DateTimeFormat>();
function clock(iso: string, timeZone: string): string {
  let f = CLOCKS.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric", minute: "2-digit" });
    CLOCKS.set(timeZone, f);
  }
  const t = Date.parse(iso);
  return Number.isFinite(t) ? f.format(t) : "";
}
const DATE = new Intl.DateTimeFormat("en-US", { weekday: "short", month: "short", day: "numeric", timeZone: "UTC" });

export function BriefsFeed({ briefs, timeZone, now }: { briefs: Brief[]; timeZone: string; now: number }) {
  if (briefs.length === 0) {
    return (
      <EmptyState title="No briefs" icon={<FileTextIcon />}>
        Briefs an agent pushes (POST /ingest/briefs) show up here, newest first.
      </EmptyState>
    );
  }
  let index = 0;
  return (
    <div className="flex flex-col gap-8">
      {groupByDay(briefs, (b) => b.published_at, timeZone, new Date(now)).map((day) => (
        <section key={day.day} aria-label={day.label} className="grid grid-cols-[120px_minmax(0,1fr)] gap-x-6 gap-y-3 max-md:grid-cols-1">
          <div className="self-start pt-1 md:sticky md:top-6">
            <h3 className="font-heading text-base leading-tight font-semibold">{day.label}</h3>
            <p className="mt-0.5 text-xs text-muted-foreground">
              {day.label === "Today" || day.label === "Yesterday" ? `${DATE.format(Date.parse(`${day.day}T12:00:00Z`))} · ` : ""}
              {plural(day.items.length, "brief")}
            </p>
          </div>
          <div className="flex min-w-0 flex-col gap-3">
            {day.items.map((b) => (
              <BriefItem key={b.id} b={b} timeZone={timeZone} now={now} index={index++} />
            ))}
          </div>
        </section>
      ))}
    </div>
  );
}

function BriefItem({ b, timeZone, now, index }: { b: Brief; timeZone: string; now: number; index: number }) {
  const r = rise(index);
  const color = cssColor(b.agent_color);
  const at = (
    <time dateTime={b.published_at} title={formatDateTime(b.published_at)} className="tabular-nums">
      {clock(b.published_at, timeZone)}
    </time>
  );

  if (b.kind === "hourly") {
    return (
      <article className={cn("flex items-baseline gap-3 rounded-2xl bg-card/70 px-4 py-2.5 ring-1 ring-foreground/6", r.className)} style={r.style}>
        <span className="w-[62px] shrink-0 text-xs text-muted-foreground">{at}</span>
        <Swatch color={b.agent_color} className="mt-[5px] size-2.5 self-start" />
        <p className="min-w-0 flex-1 text-sm">
          <span className="font-medium">{b.title}</span>
          {b.body ? <span className="text-muted-foreground"> — {preview(b.body, 160)}</span> : null}
        </p>
      </article>
    );
  }

  if (b.kind === "alert") {
    const left = expiryLeft(b.published_at, b.expires_at, now);
    return (
      <article className={cn(CARD, "relative overflow-hidden bg-destructive/[0.035] p-5 pl-6 ring-destructive/25 dark:bg-destructive/[0.06]", r.className)} style={r.style}>
        <span aria-hidden="true" className="absolute inset-y-0 left-0 w-1.5 bg-destructive" />
        <div className="flex flex-wrap items-center justify-between gap-2">
          <span className="inline-flex items-center gap-1.5 text-xs font-semibold tracking-wider text-destructive uppercase">
            <CircleAlertIcon className="size-3.5" aria-hidden="true" />
            Alert
          </span>
          <span className="flex items-center gap-2 text-xs text-muted-foreground">
            <AgentLabel name={b.agent_name} color={b.agent_color} />
            <span aria-hidden="true">·</span>
            {at}
          </span>
        </div>
        <h4 className="mt-2 font-heading text-lg leading-snug font-semibold">{b.title}</h4>
        {b.body ? <p className="mt-1 text-[15px] whitespace-pre-line text-muted-foreground">{b.body}</p> : null}
        {left ? (
          <div className="mt-4 flex flex-col gap-1.5">
            <Progress
              value={Math.round(left.share * 1000) / 10}
              aria-label={left.ms > 0 ? `${Math.round(left.share * 100)}% of its time left` : "Expired"}
              className="h-1.5 bg-destructive/12 *:data-[slot=progress-indicator]:bg-destructive"
            />
            <span className="text-xs text-muted-foreground">
              {left.ms > 0 ? `Leaves the display in ${durationLabel(left.ms)}, at ${clock(b.expires_at!, timeZone)}` : `Expired at ${clock(b.expires_at!, timeZone)}`}
            </span>
          </div>
        ) : null}
      </article>
    );
  }

  if (b.kind === "daily") {
    const { lead, bullets } = briefParts(b.body);
    return (
      <article className={cn(CARD, "overflow-hidden", r.className)} style={{ ...r.style, ...(color ? { "--agent": color } : {}) } as CSSProperties}>
        <div className="feed-agent-tint flex flex-wrap items-center justify-between gap-2 px-5 py-3">
          <span className="flex items-center gap-2 text-sm font-semibold">
            <Swatch color={b.agent_color} />
            {b.agent_name}
          </span>
          <span className="text-xs text-muted-foreground">Daily brief · {at}</span>
        </div>
        <div className="flex flex-col gap-3 px-5 pt-4 pb-5">
          <h4 className="font-heading text-xl leading-snug font-semibold tracking-tight">{b.title}</h4>
          {lead ? <p className="text-[15px] text-muted-foreground">{lead}</p> : null}
          {bullets.length ? (
            <ul className="flex flex-col gap-2.5">
              {bullets.map((point, i) => (
                <li key={i} className="flex gap-3 text-[15px] leading-snug">
                  <span aria-hidden="true" className="mt-[7px] size-2 shrink-0 rounded-full bg-primary" style={color ? { background: color } : undefined} />
                  <span className="min-w-0">{point}</span>
                </li>
              ))}
            </ul>
          ) : null}
          <AskLink question={`Tell me more about ${b.agent_name}'s "${b.title}" brief.`} label="Ask a follow-up" className="mt-1 self-start" />
        </div>
      </article>
    );
  }

  return (
    <article className={cn(CARD, "p-5", r.className)} style={r.style}>
      <div className="flex flex-wrap items-center justify-between gap-2 text-xs text-muted-foreground">
        <AgentLabel name={b.agent_name} color={b.agent_color} />
        <span>
          {b.kind === "update" ? "Update" : b.kind} · {at}
        </span>
      </div>
      <h4 className="mt-2 font-medium leading-snug">{b.title}</h4>
      {b.body ? <p className="mt-1 text-sm whitespace-pre-line text-muted-foreground">{b.body}</p> : null}
    </article>
  );
}
