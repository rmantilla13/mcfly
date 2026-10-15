import { cn } from "cn";
import { CalendarIcon, ExternalLinkIcon, MapPinIcon, Trash2Icon } from "lucide-react";
import { ConfirmAction } from "@/components/ConfirmAction";
import { EmptyState, Swatch } from "@/components/bits";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import type { FormAction } from "@/lib/action-result";
import { formatEventTime, groupEventsByDay } from "@/lib/events";
import { formatNumber, plural } from "@/lib/format";
import type { EventRow } from "@/lib/types";

// The calendar tab: every calendar an agent pushes (with a way to drop one
// whole), then the events by day in the display's time zone.
export function CalendarList({
  events,
  timeZone,
  deleteEventAction,
  deleteCalendarAction,
}: {
  events: EventRow[];
  timeZone: string;
  deleteEventAction: FormAction;
  deleteCalendarAction: FormAction;
}) {
  // One entry per (agent, calendar), the unit admin_delete_calendar removes.
  const calendars = new Map<string, { agentId: string; agentName: string; calendar: string; color: string | null; count: number }>();
  for (const e of events) {
    const key = `${e.agent_id}\u0000${e.calendar}`;
    const entry = calendars.get(key) ?? { agentId: e.agent_id, agentName: e.agent_name, calendar: e.calendar, color: e.color, count: 0 };
    entry.count += 1;
    entry.color ??= e.color;
    calendars.set(key, entry);
  }
  const days = groupEventsByDay(events, timeZone);

  if (events.length === 0) {
    return (
      <EmptyState title="No events" icon={<CalendarIcon />}>
        Events an agent pushes (POST /ingest/events) show up here by day, from a week ago to two months out.
      </EmptyState>
    );
  }

  return (
    <div className="flex flex-col gap-4 px-4">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-xs font-semibold tracking-wider text-muted-foreground uppercase">Calendars</span>
        {[...calendars.values()].map((c) => (
          <div key={`${c.agentId}-${c.calendar}`} className="flex items-center gap-1 rounded-lg border border-border py-0.5 pr-0.5 pl-2.5 text-sm">
            <Swatch color={c.color} />
            <span className="font-medium">{c.calendar}</span>
            <span className="text-xs text-muted-foreground">
              {c.agentName} · {formatNumber(c.count)}
            </span>
            <ConfirmAction
              action={deleteCalendarAction}
              fields={{ agent_id: c.agentId, calendar: c.calendar }}
              title={`Remove ${c.calendar} from ${c.agentName}?`}
              description={`Every event ${c.agentName} pushed to the ${c.calendar} calendar is removed, not only the ${plural(c.count, "one", "shown here")}. Its next push for that calendar brings them back.`}
              confirmLabel="Remove calendar"
              tone="danger"
              trigger={
                <Button variant="ghost" size="icon-xs" aria-label={`Remove the ${c.calendar} calendar from ${c.agentName}`}>
                  <Trash2Icon />
                </Button>
              }
            />
          </div>
        ))}
      </div>

      <div className="flex flex-col">
        {days.map((day, i) => (
          <div key={day.day}>
            {i > 0 ? <Separator className="my-3" /> : null}
            <div className={cn("grid grid-cols-[140px_minmax(0,1fr)] gap-x-4 max-sm:grid-cols-1", day.past && "opacity-60")}>
              <div className="pt-1">
                <div className="font-medium">{day.label}</div>
                <div className="text-xs text-muted-foreground">{day.day}</div>
              </div>
              <ul className="flex flex-col">
                {day.events.map((e) => (
                  <li key={e.id} className="flex items-start gap-3 border-b border-border py-2 last:border-b-0">
                    <span className="w-32 shrink-0 pt-0.5 text-sm text-muted-foreground tabular-nums">{formatEventTime(e, timeZone)}</span>
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="font-medium">{e.title}</span>
                        <Badge variant="outline">
                          <Swatch color={e.color} className="size-2" />
                          {e.calendar}
                        </Badge>
                        {e.url ? (
                          <a href={e.url} target="_blank" rel="noopener noreferrer" className="text-muted-foreground hover:text-foreground" aria-label={`Open ${e.title}`}>
                            <ExternalLinkIcon className="size-3.5" />
                          </a>
                        ) : null}
                      </div>
                      <div className="flex flex-wrap items-center gap-x-3 text-xs text-muted-foreground">
                        {e.location ? (
                          <span className="inline-flex items-center gap-1">
                            <MapPinIcon className="size-3" />
                            {e.location}
                          </span>
                        ) : null}
                        <span>{e.agent_name}</span>
                      </div>
                    </div>
                    <ConfirmAction
                      action={deleteEventAction}
                      fields={{ event_id: e.id }}
                      title={`Delete ${e.title}?`}
                      description="It leaves every display. The agent's next push for this calendar may bring it back."
                      confirmLabel="Delete event"
                      tone="danger"
                      trigger={
                        <Button variant="ghost" size="icon-sm" aria-label={`Delete ${e.title}`}>
                          <Trash2Icon />
                        </Button>
                      }
                    />
                  </li>
                ))}
              </ul>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
