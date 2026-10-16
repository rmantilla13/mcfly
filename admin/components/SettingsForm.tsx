"use client";

import { useId, useState } from "react";
import { toast } from "sonner";
import { LocateTimeZone } from "@/components/LocateTimeZone";
import { useFormAction } from "@/components/useFormAction";
import { Button } from "@/components/ui/button";
import { Field, FieldContent, FieldDescription, FieldError, FieldGroup, FieldLabel, FieldLegend, FieldSet } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectGroup, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Spinner } from "@/components/ui/spinner";
import type { FormAction } from "@/lib/action-result";
import { COMMON_TIMEZONES } from "@/lib/timezones";
import type { Settings } from "@/lib/types";

const SETTING_KEYS = [
  "display_name",
  "timezone",
  "briefs_keep_days",
  "quotes_keep_days",
  "news_keep_reports",
  "assistant_provider",
  "metrics_keep_days",
  "events_keep_days",
] as const;

const PROVIDERS = [
  { value: "claude", label: "Claude", hint: "Anthropic's model, through the assistant function (ANTHROPIC_API_KEY)." },
  { value: "grok", label: "Grok", hint: "xAI's model, through the same function (XAI_API_KEY)." },
];

export function SettingsForm({ action, settings }: { action: FormAction; settings: Settings }) {
  const id = useId();
  // Controlled so "Use my location" can fill it; the remount below resets it on save.
  const [timezone, setTimezone] = useState(settings.timezone);
  const { result, pending, submit, reset } = useFormAction(action, (res) => {
    if (res?.ok && res.message) toast.success(res.message);
  });

  return (
    // Remounted when the saved settings change, so the fields show what's
    // saved now rather than stale defaults.
    <form key={settings.updated_at ?? ""} onSubmit={submit} onChange={reset}>
      {/* The values this form started from; the action saves only what changed. */}
      {SETTING_KEYS.map((key) => (
        <input key={key} type="hidden" name={`was_${key}`} value={String(settings[key])} />
      ))}
      <FieldGroup>
        <FieldSet>
          <FieldLegend>Display</FieldLegend>
          <FieldGroup>
            <Field orientation="responsive">
              <FieldLabel htmlFor={`${id}-display_name`} className="min-w-48">
                Name
              </FieldLabel>
              <FieldContent>
                <Input id={`${id}-display_name`} name="display_name" defaultValue={settings.display_name} required maxLength={80} className="max-w-xs" />
                <FieldDescription>Shown on the home screen and used by the assistant when it introduces itself.</FieldDescription>
              </FieldContent>
            </Field>
            <Field orientation="responsive">
              <FieldLabel htmlFor={`${id}-timezone`} className="min-w-48">
                Time zone
              </FieldLabel>
              <FieldContent>
                <Input id={`${id}-timezone`} name="timezone" value={timezone} onChange={(e) => setTimezone(e.target.value)} required maxLength={64} list={`${id}-zones`} className="max-w-xs" spellCheck={false} />
                <datalist id={`${id}-zones`}>
                  {COMMON_TIMEZONES.map((tz) => (
                    <option key={tz} value={tz} />
                  ))}
                </datalist>
                <LocateTimeZone
                  value={timezone}
                  onFound={(zone) => {
                    setTimezone(zone);
                    reset();
                  }}
                />
                <FieldDescription>Where the display is, from your location or typed as an IANA name like America/Chicago. The clock, the day&apos;s report and retention use it.</FieldDescription>
              </FieldContent>
            </Field>
          </FieldGroup>
        </FieldSet>

        <FieldSet>
          <FieldLegend>Assistant</FieldLegend>
          <FieldGroup>
            <Field orientation="responsive">
              <FieldLabel htmlFor={`${id}-assistant_provider`} className="min-w-48">
                Answers come from
              </FieldLabel>
              <FieldContent>
                <Select name="assistant_provider" defaultValue={settings.assistant_provider}>
                  <SelectTrigger id={`${id}-assistant_provider`} className="w-48">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectGroup>
                      {PROVIDERS.map((p) => (
                        <SelectItem key={p.value} value={p.value}>
                          {p.label}
                        </SelectItem>
                      ))}
                    </SelectGroup>
                  </SelectContent>
                </Select>
                <FieldDescription>{PROVIDERS.find((p) => p.value === settings.assistant_provider)?.hint ?? "Which model answers the displays and the app."}</FieldDescription>
              </FieldContent>
            </Field>
          </FieldGroup>
        </FieldSet>

        <FieldSet>
          <FieldLegend>Retention</FieldLegend>
          <FieldDescription>Applied after every push (prune_feed). The newest quote per symbol and the newest value per metric always stay.</FieldDescription>
          <FieldGroup>
            <Field orientation="responsive">
              <FieldLabel htmlFor={`${id}-briefs_keep_days`} className="min-w-48">
                Keep briefs for
              </FieldLabel>
              <div className="flex items-center gap-2">
                <Input id={`${id}-briefs_keep_days`} name="briefs_keep_days" type="number" defaultValue={settings.briefs_keep_days} min={1} max={3650} step={1} required className="w-28" />
                <span className="text-sm text-muted-foreground">days</span>
              </div>
            </Field>
            <Field orientation="responsive">
              <FieldLabel htmlFor={`${id}-quotes_keep_days`} className="min-w-48">
                Keep quote history for
              </FieldLabel>
              <div className="flex items-center gap-2">
                <Input id={`${id}-quotes_keep_days`} name="quotes_keep_days" type="number" defaultValue={settings.quotes_keep_days} min={1} max={3650} step={1} required className="w-28" />
                <span className="text-sm text-muted-foreground">days</span>
              </div>
            </Field>
            <Field orientation="responsive">
              <FieldLabel htmlFor={`${id}-news_keep_reports`} className="min-w-48">
                Keep news reports
              </FieldLabel>
              <div className="flex items-center gap-2">
                <Input id={`${id}-news_keep_reports`} name="news_keep_reports" type="number" defaultValue={settings.news_keep_reports} min={1} max={1000} step={1} required className="w-28" />
                <span className="text-sm text-muted-foreground">newest reports</span>
              </div>
            </Field>
            <Field orientation="responsive">
              <FieldLabel htmlFor={`${id}-metrics_keep_days`} className="min-w-48">
                Keep metric history for
              </FieldLabel>
              <div className="flex items-center gap-2">
                <Input id={`${id}-metrics_keep_days`} name="metrics_keep_days" type="number" defaultValue={settings.metrics_keep_days} min={1} max={3650} step={1} required className="w-28" />
                <span className="text-sm text-muted-foreground">days</span>
              </div>
            </Field>
            <Field orientation="responsive">
              <FieldLabel htmlFor={`${id}-events_keep_days`} className="min-w-48">
                Keep past events for
              </FieldLabel>
              <div className="flex items-center gap-2">
                <Input id={`${id}-events_keep_days`} name="events_keep_days" type="number" defaultValue={settings.events_keep_days} min={1} max={3650} step={1} required className="w-28" />
                <span className="text-sm text-muted-foreground">days</span>
              </div>
            </Field>
          </FieldGroup>
        </FieldSet>

        {result && !result.ok ? <FieldError>{result.error}</FieldError> : null}
        <div className="flex items-center gap-3">
          <Button type="submit" disabled={pending}>
            {pending ? <Spinner data-icon="inline-start" /> : null}
            {pending ? "Saving…" : "Save settings"}
          </Button>
          {result?.ok && result.message ? <span className="text-sm text-muted-foreground">{result.message}</span> : null}
        </div>
      </FieldGroup>
    </form>
  );
}
