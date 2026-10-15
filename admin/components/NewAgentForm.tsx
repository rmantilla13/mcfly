"use client";

import { useState } from "react";
import { toast } from "sonner";
import { KeyReveal } from "@/components/KeyReveal";
import { useFormAction } from "@/components/useFormAction";
import { Button } from "@/components/ui/button";
import { Field, FieldDescription, FieldError, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectGroup, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Spinner } from "@/components/ui/spinner";
import type { FormAction } from "@/lib/action-result";
import type { AgentKind } from "@/lib/types";

export const KIND_OPTIONS: { value: AgentKind; label: string; hint: string }[] = [
  { value: "grok", label: "Grok", hint: "Briefs: hourly and daily notes" },
  { value: "stocks", label: "Stocks", hint: "Quotes for the Markets screen" },
  { value: "news", label: "News", hint: "Daily Pulse reports" },
  { value: "other", label: "Other", hint: "Anything else that pushes" },
];

export function KindSelect({ name, defaultValue, id }: { name: string; defaultValue: AgentKind; id?: string }) {
  return (
    <Select name={name} defaultValue={defaultValue}>
      <SelectTrigger id={id} className="w-full">
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        <SelectGroup>
          {KIND_OPTIONS.map((k) => (
            <SelectItem key={k.value} value={k.value}>
              {k.label}
            </SelectItem>
          ))}
        </SelectGroup>
      </SelectContent>
    </Select>
  );
}

// A color swatch picker that also shows the hex, so the admin can paste one.
export function ColorField({ name, defaultValue, id }: { name: string; defaultValue: string; id?: string }) {
  const [value, setValue] = useState(defaultValue);
  return (
    <div className="flex items-center gap-2">
      <input
        type="color"
        id={id}
        name={name}
        value={value}
        onChange={(e) => setValue(e.target.value)}
        className="size-8 shrink-0 cursor-pointer rounded-lg border border-input bg-transparent p-0.5 [&::-webkit-color-swatch]:rounded-md [&::-webkit-color-swatch]:border-0 [&::-webkit-color-swatch-wrapper]:p-0"
      />
      <Input
        value={value.toUpperCase()}
        onChange={(e) => {
          const v = e.target.value.trim();
          if (/^#[0-9a-f]{6}$/i.test(v)) setValue(v.toLowerCase());
        }}
        className="w-28 font-mono"
        aria-label="Hex color"
        spellCheck={false}
      />
    </div>
  );
}

export function NewAgentForm({ action, baseUrl }: { action: FormAction; baseUrl: string }) {
  const [made, setMade] = useState<{ name: string; kind: AgentKind; key: string } | null>(null);
  const { result, pending, submit } = useFormAction(action, (res, form) => {
    if (!res?.ok || !res.key) return;
    const fd = new FormData(form);
    setMade({ name: String(fd.get("name") ?? "Agent"), kind: String(fd.get("kind") ?? "other") as AgentKind, key: res.key });
    toast.success(res.message ?? "Agent created.");
    form.reset();
  });

  return (
    <div className="flex flex-col gap-5">
      <form onSubmit={submit}>
        <FieldGroup>
          <div className="grid grid-cols-[minmax(0,1fr)_160px_auto] items-end gap-4 max-md:grid-cols-1">
            <Field>
              <FieldLabel htmlFor="new-agent-name">Name</FieldLabel>
              <Input id="new-agent-name" name="name" required maxLength={80} placeholder="Market desk" autoComplete="off" />
            </Field>
            <Field>
              <FieldLabel htmlFor="new-agent-kind">Kind</FieldLabel>
              <KindSelect name="kind" defaultValue="other" id="new-agent-kind" />
            </Field>
            <Field>
              <FieldLabel htmlFor="new-agent-color">Color</FieldLabel>
              <ColorField name="color" defaultValue="#4f7cf7" id="new-agent-color" />
            </Field>
          </div>
          <FieldDescription>
            Kind only picks the icon, the color and the example below; any agent may push to any feed.
          </FieldDescription>
          {result && !result.ok ? <FieldError>{result.error}</FieldError> : null}
          <div>
            <Button type="submit" disabled={pending}>
              {pending ? <Spinner data-icon="inline-start" /> : null}
              {pending ? "Creating…" : "Create agent and show its key"}
            </Button>
          </div>
        </FieldGroup>
      </form>
      {made ? <KeyReveal agentName={made.name} kind={made.kind} apiKey={made.key} baseUrl={baseUrl} /> : null}
    </div>
  );
}
