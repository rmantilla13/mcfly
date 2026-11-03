"use client";

import { BellRingIcon, MessageCircleIcon, SendIcon } from "lucide-react";
import { useEffect, useRef, useState, useTransition } from "react";
import { toast } from "sonner";
import { EmptyState } from "@/components/bits";
import { useFormAction } from "@/components/useFormAction";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Field, FieldDescription, FieldError, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Spinner } from "@/components/ui/spinner";
import { Textarea } from "@/components/ui/textarea";
import type { ActionResult, FormAction } from "@/lib/action-result";
import { cn } from "cn";
import {
  MAX_MESSAGE,
  mergeMessages,
  notifyNote,
  pollSince,
  replyStatus,
  threadDays,
  unreadFromHome,
  type Message,
  type MessageNames,
} from "@/lib/messages";

type Actions = {
  poll: (since: string | null) => Promise<{ ok: true; messages: Message[] } | { ok: false; error: string }>;
  send: (body: string) => Promise<{ ok: true; message: Message } | { ok: false; error: string }>;
  read: (upTo: string) => Promise<ActionResult>;
  saveNames: FormAction;
  test: () => Promise<ActionResult>;
};

const POLL_MS = 5000;

// The household thread on the console: what home wrote on the left under the
// writer's name, the person's replies on the right. Polled every few
// seconds while the tab is in front; home's messages are marked read as they
// show, which clears the phone's badge too.
export function MessagesThread({
  initial,
  names,
  timeZone,
  actions,
}: {
  initial: Message[];
  names: MessageNames;
  timeZone: string;
  actions: Actions;
}) {
  const [messages, setMessages] = useState(initial);
  const [draft, setDraft] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [sending, startSending] = useTransition();
  const [nowMs, setNowMs] = useState(() => Date.now());
  const latest = useRef(messages);
  const bottom = useRef<HTMLDivElement>(null);

  useEffect(() => {
    latest.current = messages;
  }, [messages]);

  // What changed, every few seconds while the page is in front; and what
  // home wrote, marked read.
  useEffect(() => {
    let stopped = false;
    const tick = async () => {
      if (document.visibilityState !== "visible") return;
      const res = await actions.poll(pollSince(latest.current));
      if (stopped || !res.ok) return;
      const merged = mergeMessages(latest.current, res.messages);
      const unread = unreadFromHome(merged);
      const readAt = new Date().toISOString();
      setMessages(unread.length ? merged.map((m) => (m.sender_kind === "display" && !m.read_at ? { ...m, read_at: readAt } : m)) : merged);
      setNowMs(Date.now());
      if (unread.length) await actions.read(unread.at(-1)!.id);
    };
    void tick();
    const id = setInterval(tick, POLL_MS);
    return () => {
      stopped = true;
      clearInterval(id);
    };
  }, [actions]);

  const lastId = messages.at(-1)?.id;
  useEffect(() => {
    bottom.current?.scrollIntoView({ block: "end" });
  }, [lastId]);

  function send() {
    const body = draft.trim();
    if (!body) return;
    setError(null);
    startSending(async () => {
      const res = await actions.send(body);
      if (!res.ok) {
        setError(res.error);
        return;
      }
      setDraft("");
      setMessages((known) => mergeMessages(known, [res.message]));
    });
  }

  const days = threadDays(messages, nowMs, timeZone);
  const lastReply = [...messages].reverse().find((m) => m.sender_kind === "person")?.id;
  const time = (iso: string) => new Date(iso).toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit", timeZone });

  return (
    <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_340px]">
      <Card className="flex min-h-[560px] flex-col">
        <CardContent className="flex flex-1 flex-col gap-1 overflow-y-auto pt-2" style={{ maxHeight: "68vh" }}>
          {messages.length === 0 ? (
            <EmptyState title="No messages yet" icon={<MessageCircleIcon />}>
              What the family writes on the display shows up here, and on your phone as a notification. Write to them below: it shows on the
              display within seconds.
            </EmptyState>
          ) : null}
          {days.map((day) => (
            <section key={day.title} className="flex flex-col gap-1">
              <h2 className="py-3 text-center text-xs font-semibold tracking-wider text-muted-foreground uppercase">{day.title}</h2>
              {day.items.map(({ message: m, runStart }) => {
                const mine = m.sender_kind === "person";
                const note = mine ? (m.id === lastReply ? replyStatus(m) : null) : notifyNote(m);
                return (
                  <div key={m.id} className={cn("flex flex-col gap-1", mine ? "items-end pl-12" : "items-start pr-12", runStart && "mt-3")}>
                    {runStart ? (
                      <span className="px-2 text-xs font-semibold text-muted-foreground">
                        {m.sender_name} · {time(m.created_at)}
                      </span>
                    ) : null}
                    <p
                      className={cn(
                        "max-w-[520px] rounded-3xl px-4 py-2.5 text-[15px] leading-snug whitespace-pre-wrap",
                        mine ? "bg-primary text-primary-foreground" : "bg-muted text-foreground",
                      )}
                    >
                      {m.body}
                    </p>
                    {note ? <span className="px-2 text-[11px] text-muted-foreground">{note}</span> : null}
                  </div>
                );
              })}
            </section>
          ))}
          <div ref={bottom} />
        </CardContent>
        <form
          className="flex items-end gap-2 border-t p-4"
          onSubmit={(e) => {
            e.preventDefault();
            send();
          }}
        >
          <Textarea
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                send();
              }
            }}
            maxLength={MAX_MESSAGE}
            rows={1}
            placeholder={`Message home, as ${names.mine ?? "Parent"}`}
            className="min-h-11 resize-none"
            aria-label="Message home"
          />
          <Button type="submit" size="icon" className="size-11 shrink-0 rounded-full" disabled={sending || !draft.trim()} aria-label="Send">
            {sending ? <Spinner /> : <SendIcon />}
          </Button>
        </form>
        {error ? <p className="px-4 pb-4 text-sm text-destructive">{error}</p> : null}
      </Card>
      <div className="flex flex-col gap-6">
        <NamesCard names={names} action={actions.saveNames} />
        <TestCard action={actions.test} />
      </div>
    </div>
  );
}

function NamesCard({ names, action }: { names: MessageNames; action: FormAction }) {
  const { result, pending, submit } = useFormAction(action, (res) => {
    if (res?.ok && res.message) toast.success(res.message);
  });
  return (
    <Card>
      <CardHeader>
        <CardTitle>Who writes</CardTitle>
        <CardDescription>The display&apos;s Messages screen has a button a name, so you know who wrote.</CardDescription>
      </CardHeader>
      <CardContent>
        <form onSubmit={submit}>
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor="household">At home</FieldLabel>
              <Textarea id="household" name="household" rows={3} defaultValue={names.household.join("\n")} placeholder={"Mia\nLeo"} />
              <FieldDescription>A name a line, at most 8. With none, messages carry the display&apos;s name.</FieldDescription>
            </Field>
            <Field>
              <FieldLabel htmlFor="mine">You</FieldLabel>
              <Input id="mine" name="mine" maxLength={24} defaultValue={names.mine ?? ""} placeholder="Dad, Mom…" />
              <FieldDescription>Your replies are signed with this on the display. Until then: Parent.</FieldDescription>
            </Field>
            {result && !result.ok ? <FieldError>{result.error}</FieldError> : null}
            <Button type="submit" disabled={pending} className="self-start">
              {pending ? <Spinner /> : null}
              Save
            </Button>
          </FieldGroup>
        </form>
      </CardContent>
    </Card>
  );
}

function TestCard({ action }: { action: () => Promise<ActionResult> }) {
  const [pending, start] = useTransition();
  const [result, setResult] = useState<ActionResult>(null);
  return (
    <Card>
      <CardHeader>
        <CardTitle>Notifications</CardTitle>
        <CardDescription>
          A message from home goes to every phone signed in to the McFly app. Reply on the notification to answer without opening it.
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <Button
          variant="outline"
          className="self-start"
          disabled={pending}
          onClick={() =>
            start(async () => {
              setResult(await action());
            })
          }
        >
          {pending ? <Spinner /> : <BellRingIcon />}
          Send a test notification
        </Button>
        {result ? <p className={cn("text-sm", result.ok ? "text-muted-foreground" : "text-destructive")}>{result.ok ? result.message : result.error}</p> : null}
      </CardContent>
    </Card>
  );
}
