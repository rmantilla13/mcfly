"use client";

import { CalendarIcon, PauseIcon, PlayIcon, RefreshCwIcon, Trash2Icon } from "lucide-react";
import { toast } from "sonner";
import { ConfirmAction } from "@/components/ConfirmAction";
import { ColorField } from "@/components/NewAgentForm";
import { useFormAction } from "@/components/useFormAction";
import { EmptyState, Swatch, Time } from "@/components/bits";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Field, FieldDescription, FieldError, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Spinner } from "@/components/ui/spinner";
import type { FormAction } from "@/lib/action-result";
import type { CalendarSource } from "@/lib/types";

type Actions = { add: FormAction; update: FormAction; remove: FormAction; sync: FormAction };

// Calendar subscriptions: paste a calendar's iCal link, McFly reads it every
// 15 minutes and its events show on the display, the web and the apps.
export function CalendarSources({ sources, actions }: { sources: CalendarSource[]; actions: Actions }) {
  return (
    <div className="flex flex-col gap-6">
      <AddCalendar action={actions.add} />
      {sources.length === 0 ? (
        <EmptyState title="No calendars yet" icon={<CalendarIcon />}>
          Paste an iCal link above. Your events show up on the display within a minute.
        </EmptyState>
      ) : (
        <ul className="flex flex-col gap-2">
          {sources.map((s) => (
            <SourceRow key={s.id} source={s} actions={actions} />
          ))}
        </ul>
      )}
    </div>
  );
}

function AddCalendar({ action }: { action: FormAction }) {
  const { result, pending, submit } = useFormAction(action, (res, form) => {
    if (res?.ok && res.message) toast.success(res.message);
    form.reset();
  });
  return (
    <form onSubmit={submit} className="rounded-2xl border bg-card p-4">
      <FieldGroup>
        <div className="grid grid-cols-[200px_minmax(0,1fr)_auto] items-end gap-3 max-lg:grid-cols-1">
          <Field>
            <FieldLabel htmlFor="cal-name">Name</FieldLabel>
            <Input id="cal-name" name="name" required maxLength={80} placeholder="Work" autoComplete="off" />
          </Field>
          <Field>
            <FieldLabel htmlFor="cal-url">iCal link</FieldLabel>
            <Input id="cal-url" name="url" required maxLength={2000} placeholder="https://calendar.google.com/calendar/ical/…/basic.ics" autoComplete="off" spellCheck={false} />
          </Field>
          <Field>
            <FieldLabel htmlFor="cal-color">Color</FieldLabel>
            <ColorField name="color" defaultValue="#5b7cf5" id="cal-color" />
          </Field>
        </div>
        <FieldDescription>
          Google Calendar: Settings → your calendar → Integrate calendar → Secret address in iCal format. iCloud: share the
          calendar as Public and copy the link. Outlook: Settings → Calendar → Shared calendars → Publish, then the ICS link.
          The link stays on the server; this page only ever shows its host. Read-only: McFly doesn&apos;t change your calendar.
        </FieldDescription>
        {result && !result.ok ? <FieldError>{result.error}</FieldError> : null}
        <div>
          <Button type="submit" disabled={pending}>
            {pending ? <Spinner data-icon="inline-start" /> : null}
            {pending ? "Adding and reading…" : "Add calendar"}
          </Button>
        </div>
      </FieldGroup>
    </form>
  );
}

function SourceRow({ source, actions }: { source: CalendarSource; actions: Actions }) {
  const sync = useFormAction(actions.sync, (res) => res?.ok && res.message && toast.success(res.message));
  const toggle = useFormAction(actions.update, (res) => res?.ok && res.message && toast.success(res.message));
  return (
    <li className="flex flex-wrap items-center gap-x-4 gap-y-2 rounded-2xl border bg-card px-4 py-3">
      <Swatch color={source.color} className="size-3.5" />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="truncate font-semibold">{source.name}</span>
          {!source.enabled ? <Badge variant="outline">Paused</Badge> : source.last_error ? <Badge variant="warning">Needs a look</Badge> : null}
        </div>
        <div className="text-[13px] text-muted-foreground">
          {source.host} · {source.event_count} events · {source.last_synced_at ? <>synced <Time iso={source.last_synced_at} /></> : "not read yet"}
        </div>
        {source.last_error ? <div className="text-[13px] text-destructive">{source.last_error}</div> : null}
        {sync.result && !sync.result.ok ? <div className="text-[13px] text-destructive">{sync.result.error}</div> : null}
      </div>
      <div className="flex items-center gap-1">
        <form onSubmit={sync.submit}>
          <input type="hidden" name="source_id" value={source.id} />
          <Button type="submit" variant="outline" size="sm" disabled={sync.pending || !source.enabled}>
            {sync.pending ? <Spinner data-icon="inline-start" /> : <RefreshCwIcon data-icon="inline-start" />}
            Sync now
          </Button>
        </form>
        <form onSubmit={toggle.submit}>
          <input type="hidden" name="source_id" value={source.id} />
          <input type="hidden" name="enabled" value={source.enabled ? "false" : "true"} />
          <Button type="submit" variant="ghost" size="icon-sm" aria-label={source.enabled ? "Pause" : "Resume"} disabled={toggle.pending}>
            {source.enabled ? <PauseIcon /> : <PlayIcon />}
          </Button>
        </form>
        <ConfirmAction
          action={actions.remove}
          fields={{ source_id: source.id }}
          title={`Remove ${source.name}?`}
          description="Its events leave the display. Your calendar itself is untouched."
          confirmLabel="Remove"
          tone="danger"
          trigger={
            <Button variant="ghost" size="icon-sm" aria-label={`Remove ${source.name}`}>
              <Trash2Icon />
            </Button>
          }
        />
      </div>
    </li>
  );
}
