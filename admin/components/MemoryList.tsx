"use client";

import { BookOpenIcon, PencilIcon, PinIcon, PinOffIcon, Trash2Icon } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { ConfirmAction } from "@/components/ConfirmAction";
import { useFormAction } from "@/components/useFormAction";
import { AgentLabel, EmptyState, Time } from "@/components/bits";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Field, FieldError, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Select, SelectContent, SelectGroup, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Spinner } from "@/components/ui/spinner";
import { Textarea } from "@/components/ui/textarea";
import type { FormAction } from "@/lib/action-result";
import type { MemoryNote } from "@/lib/types";

type Actions = { save: FormAction; remove: FormAction };
type AgentOption = { id: string; name: string };

// What McFly remembers. Shared notes (about you) go to the assistant and to
// agents allowed to read memory; an agent's own notes stay with that agent.
export function MemoryList({ notes, agents, actions }: { notes: MemoryNote[]; agents: AgentOption[]; actions: Actions }) {
  const shared = notes.filter((n) => !n.agent_id);
  const byAgent = notes.filter((n) => n.agent_id);
  return (
    <div className="flex flex-col gap-6">
      <AddNote action={actions.save} agents={agents} />
      <section className="flex flex-col gap-3">
        <h2 className="text-xs font-bold tracking-[0.14em] text-muted-foreground uppercase">About you · {shared.length}</h2>
        {shared.length === 0 ? (
          <EmptyState title="Nothing remembered yet" icon={<BookOpenIcon />}>
            Add what McFly should always know: where you live, what you follow, how you like briefs.
          </EmptyState>
        ) : (
          <ul className="flex flex-col gap-2">
            {shared.map((n) => (
              <NoteRow key={n.id} note={n} actions={actions} />
            ))}
          </ul>
        )}
      </section>
      {byAgent.length ? (
        <section className="flex flex-col gap-3">
          <h2 className="text-xs font-bold tracking-[0.14em] text-muted-foreground uppercase">Agents&apos; own notes · {byAgent.length}</h2>
          <ul className="flex flex-col gap-2">
            {byAgent.map((n) => (
              <NoteRow key={n.id} note={n} actions={actions} />
            ))}
          </ul>
        </section>
      ) : null}
    </div>
  );
}

function AddNote({ action, agents }: { action: FormAction; agents: AgentOption[] }) {
  const [owner, setOwner] = useState("shared");
  const { result, pending, submit } = useFormAction(action, (res, form) => {
    if (res?.ok && res.message) toast.success(res.message);
    form.reset();
  });
  return (
    <form onSubmit={submit} className="rounded-2xl border bg-card p-4">
      <FieldGroup>
        <Field>
          <FieldLabel htmlFor="memory-text">Add a note</FieldLabel>
          <Textarea id="memory-text" name="text" required maxLength={2000} rows={2} placeholder="Prefers metric units. Follows the Fed and NVDA." />
        </Field>
        <div className="flex flex-wrap items-end gap-3">
          <Field className="w-60 max-sm:w-full">
            <FieldLabel htmlFor="memory-owner">For</FieldLabel>
            <Select value={owner} onValueChange={setOwner}>
              <SelectTrigger id="memory-owner" className="w-full">
                <SelectValue>{owner === "shared" ? "Everyone (about you)" : `Only ${agents.find((a) => a.id === owner)?.name ?? "an agent"}`}</SelectValue>
              </SelectTrigger>
              <SelectContent>
                <SelectGroup>
                  <SelectItem value="shared">Everyone (about you)</SelectItem>
                  {agents.map((a) => (
                    <SelectItem key={a.id} value={a.id}>
                      Only {a.name}
                    </SelectItem>
                  ))}
                </SelectGroup>
              </SelectContent>
            </Select>
            {owner !== "shared" ? <input type="hidden" name="agent_id" value={owner} /> : null}
          </Field>
          <label className="flex h-9 items-center gap-2 text-sm">
            <input type="checkbox" name="pinned" value="true" className="size-4 accent-primary" />
            Pin it
          </label>
          <span className="flex-1" />
          <Button type="submit" disabled={pending}>
            {pending ? <Spinner data-icon="inline-start" /> : null}
            {pending ? "Saving…" : "Remember this"}
          </Button>
        </div>
        {result && !result.ok ? <FieldError>{result.error}</FieldError> : null}
      </FieldGroup>
    </form>
  );
}

function NoteRow({ note, actions }: { note: MemoryNote; actions: Actions }) {
  const [editing, setEditing] = useState(false);
  const pin = useFormAction(actions.save, (res) => res?.ok && toast.success(note.pinned ? "Unpinned." : "Pinned."));
  const edit = useFormAction(actions.save, (res) => {
    if (res?.ok) {
      setEditing(false);
      toast.success("Note saved.");
    }
  });
  return (
    <li className="flex items-start gap-3 rounded-2xl border bg-card px-4 py-3">
      <div className="min-w-0 flex-1">
        {editing ? (
          <form onSubmit={edit.submit} className="flex flex-col gap-2">
            <input type="hidden" name="memory_id" value={note.id} />
            <Textarea name="text" defaultValue={note.text} maxLength={2000} rows={2} autoFocus aria-label="Note" />
            {edit.result && !edit.result.ok ? <FieldError>{edit.result.error}</FieldError> : null}
            <div className="flex gap-2">
              <Button type="submit" size="sm" disabled={edit.pending}>
                Save
              </Button>
              <Button type="button" size="sm" variant="ghost" onClick={() => setEditing(false)}>
                Cancel
              </Button>
            </div>
          </form>
        ) : (
          <p className="text-[15px] whitespace-pre-wrap">{note.text}</p>
        )}
        <div className="mt-1.5 flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
          {note.pinned ? <Badge variant="secondary">Pinned</Badge> : null}
          {note.agent_id ? <AgentLabel name={note.agent_name} color={note.agent_color} /> : null}
          {note.key ? <code className="font-mono">{note.key}</code> : null}
          <span>{note.source === "agent" ? "from an agent" : "from you"}</span>
          <span>
            · updated <Time iso={note.updated_at} />
          </span>
        </div>
      </div>
      <div className="flex shrink-0 items-center gap-1">
        <form onSubmit={pin.submit}>
          <input type="hidden" name="memory_id" value={note.id} />
          <input type="hidden" name="pinned" value={note.pinned ? "false" : "true"} />
          <Button type="submit" variant="ghost" size="icon-sm" aria-label={note.pinned ? "Unpin" : "Pin"} disabled={pin.pending}>
            {note.pinned ? <PinOffIcon /> : <PinIcon />}
          </Button>
        </form>
        <Button variant="ghost" size="icon-sm" aria-label="Edit" onClick={() => setEditing(true)}>
          <PencilIcon />
        </Button>
        <ConfirmAction
          action={actions.remove}
          fields={{ memory_id: note.id }}
          title="Delete this note?"
          description="McFly and your agents won't see it any more."
          confirmLabel="Delete"
          tone="danger"
          trigger={
            <Button variant="ghost" size="icon-sm" aria-label="Delete">
              <Trash2Icon />
            </Button>
          }
        />
      </div>
    </li>
  );
}
