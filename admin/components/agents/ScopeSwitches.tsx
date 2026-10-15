"use client";

import { BookOpenIcon, CalendarIcon, PencilLineIcon } from "lucide-react";
import { Switch } from "@/components/ui/switch";
import type { AgentScope } from "@/lib/types";

// The three things an agent may read back (or keep) through ingest. Each is
// a switch named "scope" so a form submits the granted ones.
export const SCOPE_INFO: { scope: AgentScope; label: string; hint: string; Icon: typeof CalendarIcon }[] = [
  { scope: "calendar:read", label: "Read the calendar", hint: "Your upcoming events, to plan around them", Icon: CalendarIcon },
  { scope: "memory:read", label: "Read memory", hint: "Notes about you, and its own notes", Icon: BookOpenIcon },
  { scope: "memory:write", label: "Keep notes", hint: "Remember what it did; suggest notes about you", Icon: PencilLineIcon },
];

export function ScopeSwitches({ value, onChange, idPrefix }: { value: AgentScope[]; onChange?: (next: AgentScope[]) => void; idPrefix: string }) {
  return (
    <div className="grid grid-cols-3 gap-3 max-xl:grid-cols-1">
      {SCOPE_INFO.map(({ scope, label, hint, Icon }) => {
        const id = `${idPrefix}-${scope.replace(":", "-")}`;
        const on = value.includes(scope);
        return (
          <label
            key={scope}
            htmlFor={id}
            className="flex cursor-pointer items-start gap-3 rounded-xl border bg-card px-3.5 py-3 transition-colors has-[[data-state=checked]]:border-primary/40 has-[[data-state=checked]]:bg-accent/60"
          >
            <Icon className="mt-0.5 size-4 shrink-0 text-muted-foreground" />
            <span className="min-w-0 flex-1">
              <span className="block text-sm font-medium">{label}</span>
              <span className="block text-xs text-muted-foreground">{hint}</span>
            </span>
            <Switch
              id={id}
              name="scope"
              value={scope}
              checked={on}
              onCheckedChange={(c) => onChange?.(c ? [...value, scope] : value.filter((s) => s !== scope))}
            />
          </label>
        );
      })}
    </div>
  );
}
