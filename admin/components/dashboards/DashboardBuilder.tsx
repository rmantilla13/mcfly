"use client";

import { ArrowDownIcon, ArrowUpIcon, PlusIcon, XIcon } from "lucide-react";
import Link from "next/link";
import { useEffect, useId, useState, type ReactNode } from "react";
import type { DashboardPreview } from "@/app/(console)/actions";
import { DashboardBento } from "@/components/dashboards/DashboardBento";
import { useFormAction } from "@/components/useFormAction";
import { Button } from "@/components/ui/button";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Field, FieldDescription, FieldError, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectGroup, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Spinner } from "@/components/ui/spinner";
import { Textarea } from "@/components/ui/textarea";
import type { FormAction } from "@/lib/action-result";
import {
  AGENT_HOURS,
  BRIEF_KINDS,
  CALENDAR_DAYS,
  DASHBOARD_TEMPLATES,
  MAX_PARTS,
  PART_KINDS,
  blankPart,
  describePart,
  findTemplate,
  hoursLabel,
  partKind,
  readParts,
  templateParts,
  type DashboardPart,
  type DashboardSourceOptions,
  type DashboardTemplate,
  type PartKind,
} from "@/lib/dashboard-sources";
import { parseWidgets } from "@/lib/widgets";

// The dashboard builder: pick a template, then for each part of the board
// choose where it pulls from (which symbols, metrics, projects, calendars,
// agents…). The preview beside it is the database's own drawing of the
// parts, from the real feeds, a moment after each change; saving hands the
// recipe to the database, which keeps the board drawn from then on.

type Item = { key: number; part: DashboardPart };
type Initial = { id: string; title: string; subtitle: string | null; template: string | null; parts: DashboardPart[]; widgets: unknown[] };

let nextKey = 1;
const itemsOf = (parts: DashboardPart[]): Item[] => parts.map((part) => ({ key: nextKey++, part }));
const ANY = "__any";

export function DashboardBuilder({
  options,
  saveAction,
  previewAction,
  initial,
}: {
  options: DashboardSourceOptions;
  saveAction: FormAction;
  previewAction: (parts: unknown) => Promise<DashboardPreview>;
  initial?: Initial;
}) {
  const id = useId();
  const first = DASHBOARD_TEMPLATES[0];
  const [template, setTemplate] = useState<string | null>(initial ? initial.template : first.id);
  const [title, setTitle] = useState(initial?.title ?? first.title);
  const [subtitle, setSubtitle] = useState(initial?.subtitle ?? first.subtitle ?? "");
  const [items, setItems] = useState<Item[]>(() => itemsOf(initial ? initial.parts : templateParts(first)));
  // A title or subtitle the person typed stays when they try another template.
  const [named, setNamed] = useState(!!initial);
  const { result, pending, submit } = useFormAction(saveAction);

  const parts = items.map((i) => i.part);
  const recipe = JSON.stringify(readParts(parts));

  // The preview, drawn a moment after the recipe settles; an older answer
  // never replaces a newer one.
  const [drawn, setDrawn] = useState<{ recipe: string; widgets: unknown[]; error: string | null } | null>(
    initial ? { recipe: JSON.stringify(readParts(initial.parts)), widgets: initial.widgets, error: null } : null,
  );
  useEffect(() => {
    let live = true;
    const timer = setTimeout(async () => {
      const next = JSON.parse(recipe) as DashboardPart[];
      let res: DashboardPreview = { ok: true, widgets: [] };
      if (next.length) {
        try {
          res = await previewAction(next);
        } catch {
          res = { ok: false, error: "The preview didn't draw. Try again." };
        }
      }
      if (live) setDrawn(res.ok ? { recipe, widgets: res.widgets, error: null } : { recipe, widgets: [], error: res.error });
    }, 350);
    return () => {
      live = false;
      clearTimeout(timer);
    };
  }, [recipe, previewAction]);
  const drawing = drawn?.recipe !== recipe;
  const widgets = parseWidgets(drawn?.widgets ?? []);

  const pick = (t: DashboardTemplate) => {
    setTemplate(t.id);
    setItems(itemsOf(templateParts(t)));
    if (!named) {
      setTitle(t.title);
      setSubtitle(t.subtitle ?? "");
    }
  };
  const update = (key: number, part: DashboardPart) => setItems((list) => list.map((i) => (i.key === key ? { key, part } : i)));
  const remove = (key: number) => setItems((list) => list.filter((i) => i.key !== key));
  const move = (key: number, by: -1 | 1) =>
    setItems((list) => {
      const at = list.findIndex((i) => i.key === key);
      const to = at + by;
      if (at < 0 || to < 0 || to >= list.length) return list;
      const next = [...list];
      [next[at], next[to]] = [next[to], next[at]];
      return next;
    });
  const add = (kind: PartKind) => setItems((list) => [...list, ...itemsOf([blankPart(kind)])]);
  const started = findTemplate(initial?.template);

  return (
    <div className="flex flex-col gap-6">
      {!initial ? (
        <section className="flex flex-col gap-3" aria-labelledby={`${id}-start`}>
          <h2 id={`${id}-start`} className="text-sm font-semibold">
            Start from
          </h2>
          <div className="grid grid-cols-4 gap-3 max-xl:grid-cols-3 max-lg:grid-cols-2 max-sm:gap-2" role="radiogroup" aria-labelledby={`${id}-start`}>
            {DASHBOARD_TEMPLATES.map((t) => (
              <button
                key={t.id}
                type="button"
                role="radio"
                aria-checked={t.id === template}
                onClick={() => pick(t)}
                className="flex items-start gap-3 rounded-xl border bg-card px-3.5 py-3 text-left transition-colors hover:bg-accent/40 aria-checked:border-primary/50 aria-checked:bg-accent/60"
              >
                <span className="mt-1 size-3 shrink-0 rounded-full" style={{ background: t.color }} aria-hidden="true" />
                <span className="min-w-0">
                  <span className="block text-sm font-semibold">{t.label}</span>
                  <span className="block text-xs text-muted-foreground max-sm:hidden">{t.description}</span>
                </span>
              </button>
            ))}
          </div>
        </section>
      ) : null}

      <div className="grid items-start gap-6 xl:grid-cols-[minmax(0,30rem)_minmax(0,1fr)]">
        <form onSubmit={submit} className="flex flex-col gap-5">
          {initial ? <input type="hidden" name="dashboard_id" value={initial.id} /> : null}
          <input type="hidden" name="template" value={template ?? ""} />
          <input type="hidden" name="sources" value={recipe} />

          <div className="grid grid-cols-2 gap-4 max-sm:grid-cols-1">
            <Field>
              <FieldLabel htmlFor={`${id}-title`}>Title</FieldLabel>
              <Input
                id={`${id}-title`}
                name="title"
                required
                maxLength={80}
                value={title}
                onChange={(e) => {
                  setTitle(e.target.value);
                  setNamed(true);
                }}
                autoComplete="off"
              />
            </Field>
            <Field>
              <FieldLabel htmlFor={`${id}-subtitle`}>Subtitle</FieldLabel>
              <Input
                id={`${id}-subtitle`}
                name="subtitle"
                maxLength={200}
                value={subtitle}
                placeholder="Optional"
                onChange={(e) => {
                  setSubtitle(e.target.value);
                  setNamed(true);
                }}
                autoComplete="off"
              />
            </Field>
          </div>

          <section className="flex flex-col gap-3" aria-labelledby={`${id}-parts`}>
            <div className="flex items-baseline justify-between gap-3">
              <h2 id={`${id}-parts`} className="text-sm font-semibold">
                Where it pulls from
              </h2>
              {started ? <span className="text-xs text-muted-foreground">Started from {started.label}</span> : null}
            </div>
            {items.length === 0 ? (
              <p className="rounded-xl border border-dashed px-4 py-6 text-center text-sm text-muted-foreground">Nothing on the board yet. Add a part below.</p>
            ) : null}
            {items.map((item, i) => (
              <PartCard
                key={item.key}
                part={item.part}
                options={options}
                onChange={(p) => update(item.key, p)}
                onRemove={() => remove(item.key)}
                onUp={i > 0 ? () => move(item.key, -1) : undefined}
                onDown={i < items.length - 1 ? () => move(item.key, 1) : undefined}
              />
            ))}
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button type="button" variant="outline" className="self-start" disabled={items.length >= MAX_PARTS}>
                  <PlusIcon data-icon="inline-start" />
                  Add a part
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent className="w-72">
                {PART_KINDS.map((k) => (
                  <DropdownMenuItem key={k.kind} onSelect={() => add(k.kind)} className="items-start py-1.5">
                    <span className="mt-1.5 size-2.5 shrink-0 rounded-full" style={{ background: k.color }} aria-hidden="true" />
                    <span className="flex flex-col">
                      <span className="font-medium">{k.label}</span>
                      <span className="text-xs text-muted-foreground">{k.description}</span>
                    </span>
                  </DropdownMenuItem>
                ))}
              </DropdownMenuContent>
            </DropdownMenu>
          </section>

          {result && !result.ok ? <FieldError>{result.error}</FieldError> : null}
          <div className="flex flex-wrap items-center gap-3">
            <Button type="submit" disabled={pending || recipe === "[]"}>
              {pending ? <Spinner data-icon="inline-start" /> : null}
              {initial ? (pending ? "Saving…" : "Save dashboard") : pending ? "Creating…" : "Create dashboard"}
            </Button>
            <Button asChild variant="ghost">
              <Link href={initial ? `/feed/dashboards/${initial.id}` : "/feed?tab=dashboards"}>Cancel</Link>
            </Button>
            <span className="text-xs text-muted-foreground">McFly keeps it drawn as the feeds change, on every display.</span>
          </div>
        </form>

        <section className="flex flex-col gap-3 xl:sticky xl:top-4" aria-labelledby={`${id}-preview`} aria-busy={drawing}>
          <div className="flex items-center gap-2">
            <h2 id={`${id}-preview`} className="text-sm font-semibold">
              Preview
            </h2>
            <span className="text-xs text-muted-foreground">from the live feeds, as the display draws it</span>
            {drawing ? <Spinner className="ml-auto size-3.5 text-muted-foreground" /> : null}
          </div>
          {drawn?.error ? (
            <p className="rounded-xl border border-destructive/30 px-4 py-3 text-sm text-destructive">{drawn.error}</p>
          ) : widgets.length ? (
            <div className={drawing ? "opacity-60 transition-opacity" : "transition-opacity"}>
              <DashboardBento widgets={widgets} compact />
            </div>
          ) : (
            <p className="rounded-xl border border-dashed px-4 py-10 text-center text-sm text-muted-foreground">{drawing ? "Drawing…" : "Add a part to see it here."}</p>
          )}
        </section>
      </div>
    </div>
  );
}

// ─────────────────────────── One part ───────────────────────────

function PartCard({
  part,
  options,
  onChange,
  onRemove,
  onUp,
  onDown,
}: {
  part: DashboardPart;
  options: DashboardSourceOptions;
  onChange: (p: DashboardPart) => void;
  onRemove: () => void;
  onUp?: () => void;
  onDown?: () => void;
}) {
  const kind = partKind(part.from);
  return (
    <div className="rounded-xl border bg-card p-3.5">
      <div className="flex items-start gap-2.5">
        <span className="mt-1.5 size-2.5 shrink-0 rounded-full" style={{ background: kind.color }} aria-hidden="true" />
        <div className="min-w-0 flex-1">
          <div className="text-sm font-semibold">{kind.label}</div>
          <div className="text-xs text-muted-foreground">{describePart(part, options)}</div>
        </div>
        <div className="-mt-1 -mr-1 flex shrink-0">
          <Button type="button" variant="ghost" size="icon-sm" onClick={onUp} disabled={!onUp} aria-label={`Move ${kind.label} up`}>
            <ArrowUpIcon />
          </Button>
          <Button type="button" variant="ghost" size="icon-sm" onClick={onDown} disabled={!onDown} aria-label={`Move ${kind.label} down`}>
            <ArrowDownIcon />
          </Button>
          <Button type="button" variant="ghost" size="icon-sm" onClick={onRemove} aria-label={`Remove ${kind.label}`}>
            <XIcon />
          </Button>
        </div>
      </div>
      <div className="mt-3 flex flex-col gap-3 pl-5">
        <PartFields part={part} options={options} onChange={onChange} />
      </div>
    </div>
  );
}

function PartFields({ part, options, onChange }: { part: DashboardPart; options: DashboardSourceOptions; onChange: (p: DashboardPart) => void }) {
  switch (part.from) {
    case "quotes":
      return (
        <>
          <Row label="Symbols" hint={part.symbols.length ? "In the order you picked them." : "None picked: every symbol on the display, in its order."}>
            <Chips
              value={part.symbols}
              onChange={(symbols) => onChange({ ...part, symbols })}
              options={options.symbols.map((s) => ({ value: s.symbol, label: s.symbol, hint: [s.name, s.hidden ? "hidden on the display" : null].filter(Boolean).join(" · ") }))}
              empty="No symbols yet: a markets agent's first push adds them."
            />
          </Row>
          <div className="flex flex-wrap gap-x-5 gap-y-3">
            <Row label="Show">
              <Choice value={part.show} onChange={(show) => onChange({ ...part, show })} options={[{ value: "tiles", label: "Tiles" }, { value: "chart", label: "Charts" }]} />
            </Row>
            <Limit value={part.limit} max={12} fallback={part.show === "chart" ? 1 : 8} onChange={(limit) => onChange({ ...part, limit })} />
          </div>
        </>
      );
    case "metrics": {
      const groups = [...new Set(options.metrics.map((m) => m.group).filter((g): g is string => !!g))];
      return (
        <>
          <Row label="Metrics" hint={part.keys.length ? "In the order you picked them." : part.group ? `None picked: every ${part.group} metric.` : "None picked: every metric on the display."}>
            <Chips
              value={part.keys}
              onChange={(keys) => onChange({ ...part, keys })}
              options={options.metrics.map((m) => ({ value: m.key, label: m.label, hint: [m.key, m.group, m.hidden ? "hidden on the display" : null].filter(Boolean).join(" · ") }))}
              empty="No metrics yet: an agent's first push to /ingest/metrics adds them."
            />
          </Row>
          <div className="flex flex-wrap gap-x-5 gap-y-3">
            {groups.length && !part.keys.length ? (
              <Row label="Group">
                <Pick
                  value={part.group ?? ANY}
                  onChange={(g) => onChange({ ...part, group: g === ANY ? undefined : g })}
                  options={[{ value: ANY, label: "Any group" }, ...groups.map((g) => ({ value: g, label: g }))]}
                />
              </Row>
            ) : null}
            <Row label="Show">
              <Choice value={part.show} onChange={(show) => onChange({ ...part, show })} options={[{ value: "tiles", label: "Tiles" }, { value: "chart", label: "Charts" }]} />
            </Row>
            <Limit value={part.limit} max={12} fallback={part.show === "chart" ? 2 : 8} onChange={(limit) => onChange({ ...part, limit })} />
          </div>
        </>
      );
    }
    case "projects":
      return (
        <>
          <Row label="Projects" hint={part.projects.length ? "In the order you picked them." : "None picked: the active and blocked ones."}>
            <Chips
              value={part.projects}
              onChange={(projects) => onChange({ ...part, projects })}
              options={options.projects.map((p) => ({ value: p.id, label: p.name, hint: `${p.status} · ${p.agent_name}` }))}
              empty="No projects yet: an agent's first push to /ingest/projects adds them."
            />
          </Row>
          <div className="flex flex-wrap gap-x-5 gap-y-3">
            <Row label="Show">
              <Choice value={part.show} onChange={(show) => onChange({ ...part, show })} options={[{ value: "progress", label: "Progress" }, { value: "list", label: "A list" }]} />
            </Row>
            <Limit value={part.limit} max={12} fallback={6} onChange={(limit) => onChange({ ...part, limit })} />
          </div>
          {part.show === "list" ? <Title value={part.title} placeholder="Projects" onChange={(title) => onChange({ ...part, title })} /> : null}
        </>
      );
    case "calendar":
      return (
        <>
          <Row label="Calendars" hint={part.calendars.length ? undefined : "None picked: every calendar."}>
            <Chips
              value={part.calendars}
              onChange={(calendars) => onChange({ ...part, calendars })}
              options={options.calendars.map((c) => ({ value: c, label: c }))}
              empty="No calendars yet: add one under Calendars, or have an agent push events."
            />
          </Row>
          <div className="flex flex-wrap gap-x-5 gap-y-3">
            <Row label="How far ahead">
              <Pick
                value={String(part.days)}
                onChange={(d) => onChange({ ...part, days: Number(d) })}
                options={CALENDAR_DAYS.map((d) => ({ value: String(d), label: d === 1 ? "Today" : d === 2 ? "Today and tomorrow" : d === 7 ? "A week" : d === 14 ? "Two weeks" : d === 31 ? "A month" : `${d} days` }))}
              />
            </Row>
            <Limit value={part.limit} max={20} fallback={8} onChange={(limit) => onChange({ ...part, limit })} />
          </div>
          <Title value={part.title} placeholder={part.days === 1 ? "Today" : part.days === 2 ? "Today and tomorrow" : `Next ${part.days} days`} onChange={(title) => onChange({ ...part, title })} />
        </>
      );
    case "todos":
      return (
        <>
          <div className="flex flex-wrap gap-x-5 gap-y-3">
            <Row label="Which">
              <Choice
                value={part.kind}
                onChange={(kind) => onChange({ ...part, kind })}
                options={[
                  { value: "all", label: "Both" },
                  { value: "todo", label: "Todos" },
                  { value: "reminder", label: "Reminders" },
                ]}
              />
            </Row>
            <Limit value={part.limit} max={20} fallback={8} onChange={(limit) => onChange({ ...part, limit })} />
          </div>
          <Title value={part.title} placeholder={part.kind === "reminder" ? "Reminders" : "To do"} onChange={(title) => onChange({ ...part, title })} />
        </>
      );
    case "news":
      return (
        <>
          <div className="flex flex-wrap gap-x-5 gap-y-3">
            <Row label="Section">
              <Pick
                value={part.section ?? ANY}
                onChange={(s) => onChange({ ...part, section: s === ANY ? undefined : s })}
                options={[{ value: ANY, label: "The top headlines" }, ...options.news_sections.map((s) => ({ value: s.key, label: s.name }))]}
              />
            </Row>
            <Limit value={part.limit} max={20} fallback={5} onChange={(limit) => onChange({ ...part, limit })} />
          </div>
          <Title value={part.title} placeholder="Headlines" onChange={(title) => onChange({ ...part, title })} />
        </>
      );
    case "brief":
      return (
        <>
          <div className="flex flex-wrap gap-x-5 gap-y-3">
            <Row label="Kind">
              <Pick
                value={part.kind ?? ANY}
                onChange={(k) => onChange({ ...part, kind: k === ANY ? undefined : (k as (typeof BRIEF_KINDS)[number]) })}
                options={[{ value: ANY, label: "Any kind" }, ...BRIEF_KINDS.map((k) => ({ value: k, label: k[0].toUpperCase() + k.slice(1) }))]}
              />
            </Row>
            <Row label="From">
              <Pick
                value={part.agent ?? ANY}
                onChange={(a) => onChange({ ...part, agent: a === ANY ? undefined : a })}
                options={[{ value: ANY, label: "Any agent" }, ...options.agents.map((a) => ({ value: a.id, label: a.name }))]}
              />
            </Row>
          </div>
          <Title value={part.title} placeholder="The brief's own title" onChange={(title) => onChange({ ...part, title })} />
        </>
      );
    case "agents":
      return (
        <>
          <Row label="Agents" hint={part.agents.length ? undefined : "None picked: every agent with a key."}>
            <Chips
              value={part.agents}
              onChange={(agents) => onChange({ ...part, agents })}
              options={options.agents.map((a) => ({ value: a.id, label: a.name, hint: a.has_key ? undefined : "no key" }))}
              empty="No agents yet."
            />
          </Row>
          <Row label="Quiet after">
            <Choice value={part.hours} onChange={(hours) => onChange({ ...part, hours })} options={AGENT_HOURS.map((h) => ({ value: h, label: hoursLabel(h) }))} />
          </Row>
        </>
      );
    case "note":
      return (
        <>
          <Title value={part.title} placeholder="Optional" onChange={(title) => onChange({ ...part, title })} />
          <NoteBody value={part.body} onChange={(body) => onChange({ ...part, body })} />
        </>
      );
  }
}

// ─────────────────────────── Fields ───────────────────────────

function Row({ label, hint, children }: { label: string; hint?: string; children: ReactNode }) {
  return (
    <div className="flex flex-col gap-1.5">
      <span className="text-xs font-medium text-muted-foreground">{label}</span>
      {children}
      {hint ? <span className="text-xs text-muted-foreground">{hint}</span> : null}
    </div>
  );
}

// Toggles for a list of names, kept in the order they were picked. A name
// picked earlier that no longer comes up (a symbol since deleted) stays, so
// it can be taken off.
function Chips({ value, onChange, options, empty }: { value: string[]; onChange: (v: string[]) => void; options: { value: string; label: string; hint?: string }[]; empty: string }) {
  const known = new Set(options.map((o) => o.value));
  const all = [...options, ...value.filter((v) => !known.has(v)).map((v) => ({ value: v, label: v, hint: "not seen lately" }))];
  if (!all.length) return <span className="text-xs text-muted-foreground">{empty}</span>;
  return (
    <div className="flex flex-wrap gap-1.5">
      {all.map((o) => {
        const on = value.includes(o.value);
        return (
          <button
            key={o.value}
            type="button"
            aria-pressed={on}
            title={o.hint || undefined}
            onClick={() => onChange(on ? value.filter((v) => v !== o.value) : [...value, o.value])}
            className="rounded-full border bg-background px-2.5 py-1 text-xs text-muted-foreground transition-colors hover:bg-accent/50 hover:text-foreground aria-pressed:border-primary/50 aria-pressed:bg-primary/10 aria-pressed:text-foreground"
          >
            {o.label}
            {on && value.length > 1 ? <span className="ml-1 tabular-nums opacity-60">{value.indexOf(o.value) + 1}</span> : null}
          </button>
        );
      })}
    </div>
  );
}

function Choice<T extends string | number>({ value, onChange, options }: { value: T; onChange: (v: T) => void; options: { value: T; label: string }[] }) {
  return (
    <div className="inline-flex w-fit rounded-lg border bg-background p-0.5" role="radiogroup">
      {options.map((o) => (
        <button
          key={String(o.value)}
          type="button"
          role="radio"
          aria-checked={o.value === value}
          onClick={() => onChange(o.value)}
          className="rounded-md px-2.5 py-1 text-xs text-muted-foreground transition-colors hover:text-foreground aria-checked:bg-accent aria-checked:font-medium aria-checked:text-foreground"
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

function Pick({ value, onChange, options }: { value: string; onChange: (v: string) => void; options: { value: string; label: string }[] }) {
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger size="sm" className="min-w-36">
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        <SelectGroup>
          {options.map((o) => (
            <SelectItem key={o.value} value={o.value}>
              {o.label}
            </SelectItem>
          ))}
        </SelectGroup>
      </SelectContent>
    </Select>
  );
}

function Limit({ value, max, fallback, onChange }: { value: number | undefined; max: number; fallback: number; onChange: (v: number | undefined) => void }) {
  const id = useId();
  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={id} className="text-xs font-medium text-muted-foreground">
        At most
      </label>
      <Input
        id={id}
        type="number"
        min={1}
        max={max}
        step={1}
        value={value ?? ""}
        placeholder={String(fallback)}
        onChange={(e) => {
          const n = Number(e.target.value);
          onChange(e.target.value === "" || !Number.isFinite(n) ? undefined : Math.min(max, Math.max(1, Math.round(n))));
        }}
        className="h-7 w-20 text-sm"
      />
    </div>
  );
}

function Title({ value, placeholder, onChange }: { value: string | undefined; placeholder: string; onChange: (v: string | undefined) => void }) {
  const id = useId();
  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={id} className="text-xs font-medium text-muted-foreground">
        Title
      </label>
      <Input id={id} value={value ?? ""} maxLength={80} placeholder={placeholder} onChange={(e) => onChange(e.target.value || undefined)} className="h-7 text-sm" autoComplete="off" />
    </div>
  );
}

function NoteBody({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const id = useId();
  return (
    <Field>
      <FieldLabel htmlFor={id} className="text-xs font-medium text-muted-foreground">
        Words
      </FieldLabel>
      <Textarea id={id} value={value} maxLength={2000} rows={3} onChange={(e) => onChange(e.target.value)} placeholder="Deploy window tonight, 9 to 10 PM." />
      {!value.trim() ? <FieldDescription>A note with no words is left off the board.</FieldDescription> : null}
    </Field>
  );
}
