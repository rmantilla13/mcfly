"use client";

import { CheckCircle2Icon, PauseIcon, PencilIcon, PlayIcon, SparklesIcon, Trash2Icon, XCircleIcon, ZapIcon } from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { ConfirmAction } from "@/components/ConfirmAction";
import { ScopeSwitches } from "@/components/agents/ScopeSwitches";
import { ColorField } from "@/components/NewAgentForm";
import { useFormAction } from "@/components/useFormAction";
import { EmptyState, Swatch, Time } from "@/components/bits";
import { ThinkingText } from "@/components/today/ThinkingText";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Field, FieldDescription, FieldError, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Spinner } from "@/components/ui/spinner";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";
import type { FormAction } from "@/lib/action-result";
import { BOT_STARTERS, SCHEDULES, scheduleLabel, type BotStarter } from "@/lib/bots";
import type { AgentScope, Bot } from "@/lib/types";

type Actions = { save: FormAction; enable: FormAction; remove: FormAction; run: FormAction };

const hhmm = (m: number | null) => (m == null ? "" : `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`);

// Grok bots: McFly asks Grok (with web and X search) on each bot's schedule
// and puts the answer on the display as a brief or a Daily Pulse report.
export function BotsPanel({ bots, actions, xaiReady }: { bots: Bot[]; actions: Actions; xaiReady: boolean | null }) {
  const [draft, setDraft] = useState<BotStarter | Bot | null>(null);
  return (
    <div className="flex flex-col gap-6">
      {xaiReady === false ? (
        <div className="rounded-2xl border border-warning/30 bg-warning/10 px-4 py-3 text-sm text-warning">
          Add your xAI API key before bots can run: Supabase → Edge Functions → Secrets → <code className="font-mono">XAI_API_KEY</code>.
        </div>
      ) : null}

      <section className="flex flex-col gap-3">
        <h2 className="text-xs font-bold tracking-[0.14em] text-muted-foreground uppercase">Start from</h2>
        <div className="grid grid-cols-4 gap-3 max-xl:grid-cols-2 max-sm:grid-cols-1">
          {BOT_STARTERS.map((s) => (
            <button
              key={s.id}
              type="button"
              onClick={() => setDraft(s)}
              className="flex flex-col gap-1 rounded-xl border bg-card px-3.5 py-3 text-left transition-colors hover:bg-accent/40"
            >
              <span className="flex items-center gap-2 text-sm font-semibold">
                <span className="size-2.5 rounded-full" style={{ background: s.color }} />
                {s.label}
              </span>
              <span className="text-xs text-muted-foreground">{scheduleLabel(s.every_minutes, s.at_minute)} · {s.output === "news" ? "a report" : "a brief"}</span>
            </button>
          ))}
        </div>
        {!draft ? (
          <div>
            <Button variant="outline" onClick={() => setDraft({ ...BOT_STARTERS[0], id: "blank", label: "", name: "", prompt: "" })}>
              <SparklesIcon data-icon="inline-start" />
              Start from scratch
            </Button>
          </div>
        ) : null}
      </section>

      {draft ? <BotForm key={"agent_id" in draft ? draft.id : draft.id + "-new"} bot={draft} action={actions.save} onDone={() => setDraft(null)} /> : null}

      <section className="flex flex-col gap-3">
        <h2 className="text-xs font-bold tracking-[0.14em] text-muted-foreground uppercase">Your bots · {bots.length}</h2>
        {bots.length === 0 ? (
          <EmptyState title="No bots yet" icon={<ZapIcon />}>
            Pick a starter above. McFly runs it on schedule and its reports land on the display.
          </EmptyState>
        ) : (
          <ul className="flex flex-col gap-3">
            {bots.map((b) => (
              <BotCard key={b.id} bot={b} actions={actions} onEdit={() => setDraft(b)} />
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}

function Toggle({ name, label, initial }: { name: string; label: string; initial: boolean }) {
  const [on, setOn] = useState(initial);
  return (
    <label className="flex items-center gap-2.5 text-sm">
      <input type="hidden" name={name} value={on ? "true" : "false"} />
      <Switch checked={on} onCheckedChange={setOn} aria-label={label} />
      {label}
    </label>
  );
}

function BotForm({ bot, action, onDone }: { bot: BotStarter | Bot; action: FormAction; onDone: () => void }) {
  const existing = "agent_id" in bot ? bot : null;
  const [scopes, setScopes] = useState<AgentScope[]>(bot.scopes);
  const { result, pending, submit } = useFormAction(action, (res) => {
    if (res?.ok && res.message) toast.success(res.message);
    onDone();
  });
  return (
    <form onSubmit={submit} className="rounded-2xl border bg-card p-4">
      {existing ? <input type="hidden" name="bot_id" value={existing.id} /> : null}
      <FieldGroup>
        <div className="grid grid-cols-[minmax(0,1fr)_auto] items-end gap-3 max-md:grid-cols-1">
          <Field>
            <FieldLabel htmlFor="bot-name">Name</FieldLabel>
            <Input id="bot-name" name="name" required maxLength={80} defaultValue={bot.name} placeholder="Morning brief" autoComplete="off" />
          </Field>
          <Field>
            <FieldLabel htmlFor="bot-color">Color</FieldLabel>
            <ColorField name="color" defaultValue={bot.color.toLowerCase()} id="bot-color" />
          </Field>
        </div>
        <Field>
          <FieldLabel htmlFor="bot-prompt">What it does</FieldLabel>
          <Textarea id="bot-prompt" name="prompt" required minLength={10} maxLength={8000} rows={4} defaultValue={bot.prompt} />
          <FieldDescription>Written to Grok as-is. It can search the web and X, and sees the time and, if allowed below, your notes and calendar.</FieldDescription>
        </Field>
        <div className="grid grid-cols-3 gap-3 max-md:grid-cols-1">
          <Field>
            <FieldLabel htmlFor="bot-output">It writes</FieldLabel>
            <select id="bot-output" name="output" defaultValue={bot.output} className="h-9 rounded-lg border border-input bg-transparent px-2.5 text-sm">
              <option value="brief">A brief</option>
              <option value="news">A Daily Pulse report</option>
            </select>
          </Field>
          <Field>
            <FieldLabel htmlFor="bot-every">How often</FieldLabel>
            <select id="bot-every" name="every_minutes" defaultValue={String(bot.every_minutes)} className="h-9 rounded-lg border border-input bg-transparent px-2.5 text-sm">
              {SCHEDULES.map((s) => (
                <option key={s.minutes} value={s.minutes}>
                  {s.label}
                </option>
              ))}
            </select>
          </Field>
          <Field>
            <FieldLabel htmlFor="bot-at">Starting at (optional)</FieldLabel>
            <Input id="bot-at" name="at_time" type="time" defaultValue={hhmm(bot.at_minute)} />
          </Field>
        </div>
        <div className="flex flex-wrap gap-6">
          <Toggle name="web_search" label="Search the web" initial={bot.web_search} />
          <Toggle name="x_search" label="Search X" initial={bot.x_search} />
        </div>
        <Field>
          <FieldLabel>What it may read</FieldLabel>
          <ScopeSwitches value={scopes} onChange={setScopes} idPrefix="bot" />
        </Field>
        <input type="hidden" name="model" value={existing?.model ?? ""} />
        {result && !result.ok ? <FieldError>{result.error}</FieldError> : null}
        <div className="flex gap-2">
          <Button type="submit" disabled={pending}>
            {pending ? <Spinner data-icon="inline-start" /> : null}
            {existing ? "Save bot" : "Create bot"}
          </Button>
          <Button type="button" variant="ghost" onClick={onDone}>
            Cancel
          </Button>
        </div>
      </FieldGroup>
    </form>
  );
}

// What a run is up to, as far as the page can tell: it hears nothing until
// the run is done (up to two minutes), so the words move on with the time.
// Grok searches, reads what it found, then writes.
const RUN_STAGES_MS = [0, 20_000, 45_000, 90_000];

function runStage(bot: Bot, stage: number): string {
  const where = [bot.web_search && "the web", bot.x_search && "X"].filter(Boolean).join(" and ");
  const writes = bot.output === "news" ? "the Pulse report" : "the brief";
  return [
    where ? `Grok is searching ${where}…` : "Grok is thinking it over…",
    where ? "Reading what it found…" : "Working it through…",
    `Writing ${writes}…`,
    "Nearly there. A run can take up to two minutes…",
  ][stage];
}

// Shown only while a run is going, so each run starts from the first words.
function RunStatus({ bot }: { bot: Bot }) {
  const [stage, setStage] = useState(0);
  useEffect(() => {
    const timers = RUN_STAGES_MS.slice(1).map((at, i) => setTimeout(() => setStage(i + 1), at));
    return () => timers.forEach(clearTimeout);
  }, []);
  return (
    <p className="flex items-center gap-2 text-sm" role="status">
      <SparklesIcon className="size-3.5 shrink-0 text-muted-foreground" aria-hidden="true" />
      <ThinkingText text={runStage(bot, stage)} />
    </p>
  );
}

function BotCard({ bot, actions, onEdit }: { bot: Bot; actions: Actions; onEdit: () => void }) {
  const run = useFormAction(actions.run, (res) => res?.ok && res.message && toast.success(res.message));
  const enable = useFormAction(actions.enable, (res) => res?.ok && res.message && toast.success(res.message));
  return (
    <li className="flex flex-col gap-3 rounded-2xl border bg-card px-4 py-3.5">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
        <Swatch color={bot.color} className="size-3.5" />
        <span className="font-semibold">{bot.name}</span>
        {!bot.enabled ? <Badge variant="outline">Paused</Badge> : bot.last_status === "error" ? <Badge variant="warning">Last run failed</Badge> : null}
        <span className="text-[13px] text-muted-foreground">
          {scheduleLabel(bot.every_minutes, bot.at_minute)} · {bot.output === "news" ? "Daily Pulse report" : "brief"}
          {bot.web_search || bot.x_search ? ` · searches ${[bot.web_search && "the web", bot.x_search && "X"].filter(Boolean).join(" and ")}` : ""}
        </span>
        <span className="flex-1" />
        <form onSubmit={run.submit}>
          <input type="hidden" name="bot_id" value={bot.id} />
          <Button type="submit" size="sm" variant="outline" disabled={run.pending}>
            {run.pending ? <Spinner data-icon="inline-start" /> : <PlayIcon data-icon="inline-start" />}
            {run.pending ? "Running…" : "Run now"}
          </Button>
        </form>
        <form onSubmit={enable.submit}>
          <input type="hidden" name="bot_id" value={bot.id} />
          <input type="hidden" name="enabled" value={bot.enabled ? "false" : "true"} />
          <Button type="submit" size="icon-sm" variant="ghost" aria-label={bot.enabled ? "Pause" : "Resume"} disabled={enable.pending}>
            {bot.enabled ? <PauseIcon /> : <PlayIcon />}
          </Button>
        </form>
        <Button size="icon-sm" variant="ghost" aria-label="Edit" onClick={onEdit}>
          <PencilIcon />
        </Button>
        <ConfirmAction
          action={actions.remove}
          fields={{ bot_id: bot.id }}
          title={`Delete ${bot.name}?`}
          description="The bot and everything it wrote leave the display."
          confirmLabel="Delete bot"
          tone="danger"
          trigger={
            <Button size="icon-sm" variant="ghost" aria-label={`Delete ${bot.name}`}>
              <Trash2Icon />
            </Button>
          }
        />
      </div>
      {run.pending ? <RunStatus bot={bot} /> : <p className="line-clamp-2 text-sm text-muted-foreground">{bot.prompt}</p>}
      {run.result && !run.result.ok && !run.pending ? <p className="text-sm text-destructive">{run.result.error}</p> : null}
      <div className="flex flex-wrap gap-x-4 gap-y-1 text-[13px] text-muted-foreground">
        <span>{bot.enabled ? <>Next run <Time iso={bot.next_run_at} /></> : "Paused"}</span>
        <span>Last run {bot.last_run_at ? <Time iso={bot.last_run_at} /> : "never"}</span>
        <span>{bot.runs_7d} runs this week</span>
      </div>
      {bot.runs.length ? (
        <ul className="flex flex-col gap-1 border-t pt-2">
          {bot.runs.map((r) => (
            <li key={r.id} className="flex items-center gap-2 text-[13px]">
              {r.status === "ok" ? (
                <CheckCircle2Icon className="size-3.5 text-success" />
              ) : r.status === "error" ? (
                <XCircleIcon className="size-3.5 text-destructive" />
              ) : (
                <Spinner className="size-3.5" />
              )}
              <span className="truncate">{r.status === "error" ? r.error : r.title ?? "Running…"}</span>
              <span className="ml-auto shrink-0 text-muted-foreground">
                {r.sources ? `${r.sources} sources · ` : ""}
                <Time iso={r.started_at} />
              </span>
            </li>
          ))}
        </ul>
      ) : null}
    </li>
  );
}
