"use client";

import { useState } from "react";
import { toast } from "sonner";
import { AgentSetup } from "@/components/agents/AgentSetup";
import { ScopeSwitches } from "@/components/agents/ScopeSwitches";
import { useFormAction } from "@/components/useFormAction";
import { Button } from "@/components/ui/button";
import { Field, FieldDescription, FieldError, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectGroup, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Spinner } from "@/components/ui/spinner";
import type { FormAction } from "@/lib/action-result";
import { AGENT_TEMPLATES, type AgentTemplate } from "@/lib/templates";
import type { AgentKind, AgentScope } from "@/lib/types";

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

// The new-agent wizard: pick what it's for (a template fills the rest), name
// it, choose what it may read, then the setup panel takes over.
export function NewAgentForm({ action, baseUrl, demo = false }: { action: FormAction; baseUrl: string; demo?: boolean }) {
  const [template, setTemplate] = useState<AgentTemplate>(AGENT_TEMPLATES[0]);
  const [scopes, setScopes] = useState<AgentScope[]>(AGENT_TEMPLATES[0].scopes);
  const [made, setMade] = useState<{ id: string; name: string; key: string; template: AgentTemplate; scopes: AgentScope[] } | null>(null);
  const { result, pending, submit } = useFormAction(action, (res, form) => {
    if (!res?.ok || !res.key || !res.agentId) return;
    const fd = new FormData(form);
    setMade({ id: res.agentId, name: String(fd.get("name") ?? "Agent"), key: res.key, template, scopes });
    toast.success(res.message ?? "Agent created.");
  });

  const pick = (t: AgentTemplate) => {
    setTemplate(t);
    setScopes(t.scopes);
    setMade(null);
  };

  return (
    <div className="flex flex-col gap-5">
      <div className="grid grid-cols-3 gap-3 max-lg:grid-cols-2 max-sm:grid-cols-1" role="radiogroup" aria-label="What is it for?">
        {AGENT_TEMPLATES.map((t) => (
          <button
            key={t.id}
            type="button"
            role="radio"
            aria-checked={t.id === template.id}
            onClick={() => pick(t)}
            className="flex items-start gap-3 rounded-xl border bg-card px-3.5 py-3 text-left transition-colors hover:bg-accent/40 aria-checked:border-primary/50 aria-checked:bg-accent/60"
          >
            <span className="mt-1 size-3 shrink-0 rounded-full" style={{ background: t.color }} aria-hidden="true" />
            <span className="min-w-0">
              <span className="block text-sm font-semibold">{t.label}</span>
              <span className="block text-xs text-muted-foreground">{t.description}</span>
            </span>
          </button>
        ))}
      </div>

      {/* Remounted per template so the fields take its defaults. */}
      <form key={template.id} onSubmit={submit}>
        <FieldGroup>
          <input type="hidden" name="kind" value={template.kind} />
          <div className="grid grid-cols-[minmax(0,1fr)_auto] items-end gap-4 max-md:grid-cols-1">
            <Field>
              <FieldLabel htmlFor="new-agent-name">Name</FieldLabel>
              <Input id="new-agent-name" name="name" required maxLength={80} defaultValue={template.name} placeholder="Weather bot" autoComplete="off" />
            </Field>
            <Field>
              <FieldLabel htmlFor="new-agent-color">Color</FieldLabel>
              <ColorField name="color" defaultValue={template.color.toLowerCase()} id="new-agent-color" />
            </Field>
          </div>
          <Field>
            <FieldLabel>What it may read</FieldLabel>
            <ScopeSwitches value={scopes} onChange={setScopes} idPrefix="new-agent" />
            <FieldDescription>Every agent may push to any feed. These let it read back; change them any time.</FieldDescription>
          </Field>
          {result && !result.ok ? <FieldError>{result.error}</FieldError> : null}
          <div>
            <Button type="submit" disabled={pending}>
              {pending ? <Spinner data-icon="inline-start" /> : null}
              {pending ? "Creating…" : "Create agent"}
            </Button>
          </div>
        </FieldGroup>
      </form>
      {made ? (
        <AgentSetup agentId={made.id} name={made.name} template={made.template} scopes={made.scopes} apiKey={made.key} baseUrl={baseUrl} demo={demo} />
      ) : null}
    </div>
  );
}
