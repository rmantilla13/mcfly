"use client";

import { LinkIcon, MessageCircleQuestionIcon } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState, useTransition } from "react";
import { toast } from "sonner";
import { answerAskAction } from "@/app/(console)/actions";
import { Button } from "@/components/ui/button";
import type { ActionResult } from "@/lib/action-result";
import { answeredElsewhere, openAsks, questionChanged, type OpenAsk } from "@/lib/asks";
import { dateFormat } from "@/lib/events";
import { agoLabel } from "@/lib/insights";
import { Tile } from "./Tile";
import { useNow } from "./TodayView";

// What the agents are waiting on (lib/asks.ts), over every Today layout: a
// tile per question with a button per choice, the first the main one. A
// click hides it at once and answers it six seconds later unless Undo (on
// the toast) takes it back, as on the display. The toast goes when the
// answer does, and an Undo that comes too late says it was already sent.
// Going to another console page sends what's waiting straight away; a
// reload, a closed tab or a link out of the console asks first, then tries
// to send it as the page goes (that request may not outlive the page, and
// then the question is still waiting next time). The answer goes with the
// question as it was shown, and a refusal says why: another screen got there
// first (with what), the question was taken back or ran out, or the agent
// changed it, and then the page reads its data again and shows it as it now
// stands. An answer that couldn't be sent brings its question back.

const UNDO_MS = 6000;

export function AsksBand({ asks, nowMs, timeZone }: { asks: OpenAsk[]; nowMs: number; timeZone: string }) {
  const now = useNow(nowMs, 60_000);
  const router = useRouter();
  const [hidden, setHidden] = useState<ReadonlySet<string>>(new Set());
  // The answers waiting out their undo, by ask; `send` sends one now.
  const waiting = useRef(new Map<string, { timer: ReturnType<typeof setTimeout>; send: () => void }>());
  const [, startTransition] = useTransition();

  const show = (id: string, shown: boolean) =>
    setHidden((h) => {
      const next = new Set(h);
      if (shown) next.delete(id);
      else next.add(id);
      return next;
    });

  // Anything still waiting out its undo goes when the band does. A reload or
  // a closed tab doesn't unmount it, so while an answer waits the browser
  // asks before leaving, and if the page goes anyway it is sent on the way
  // out, as well as a request can be from a page that is closing.
  useEffect(() => {
    const pending = waiting.current;
    const flush = () => {
      for (const { send } of [...pending.values()]) send();
    };
    const warn = (e: BeforeUnloadEvent) => {
      if (pending.size === 0) return;
      e.preventDefault();
      e.returnValue = ""; // what Safari and older browsers look for
    };
    window.addEventListener("beforeunload", warn);
    window.addEventListener("pagehide", flush);
    return () => {
      window.removeEventListener("beforeunload", warn);
      window.removeEventListener("pagehide", flush);
      flush();
    };
  }, []);

  // Sends an answer whose undo is over, and says so if it didn't land.
  const deliver = (id: string, choice: string, question: string) =>
    startTransition(async () => {
      let result: ActionResult;
      try {
        result = await answerAskAction(id, choice, question);
      } catch {
        // The request never got an answer (offline, a dropped connection):
        // the question comes back rather than the page failing.
        show(id, true);
        toast.error("Couldn't send that answer, so the question is back.");
        return;
      }
      if (result?.ok) return;
      const error = result?.error ?? "";
      const first = answeredElsewhere(error);
      if (first) toast(`Already answered on another screen: ${first}`);
      else if (questionChanged(error)) {
        // Back with the page's data read again, so it shows the question as
        // the agent has it now.
        startTransition(() => {
          show(id, true);
          router.refresh();
        });
        toast("The agent changed that question, so here it is again.");
      } else if (/took this question back|ran out/i.test(error)) toast("That question was taken back.");
      else {
        show(id, true);
        toast.error(error || "Couldn't send that answer, so the question is back.");
      }
    });

  const answer = (ask: OpenAsk, choice: string) => {
    show(ask.id, false);
    const toastId = toast(ask.agent_name ? `Told ${ask.agent_name}: ${choice}` : `Answered: ${choice}`, {
      duration: UNDO_MS,
      action: {
        label: "Undo",
        onClick: () => {
          const w = waiting.current.get(ask.id);
          if (w?.send !== send) {
            // It went as the toast was leaving: say so rather than seem to
            // have taken it back.
            toast("Already sent, so it can't be undone.");
            return;
          }
          clearTimeout(w.timer);
          waiting.current.delete(ask.id);
          show(ask.id, true);
        },
      },
    });
    // The question as the person saw it: answer_ask refuses the answer if the
    // agent has changed it since. The toast goes with the answer, so its Undo
    // is never left up after it can't undo anything (sonner holds a toast
    // open while it's hovered or the tab is hidden; this timer doesn't wait).
    const question = ask.question;
    const send = () => {
      const w = waiting.current.get(ask.id);
      if (w?.send !== send) return; // sent already, or undone
      clearTimeout(w.timer);
      waiting.current.delete(ask.id);
      toast.dismiss(toastId);
      deliver(ask.id, choice, question);
    };
    waiting.current.set(ask.id, { timer: setTimeout(send, UNDO_MS), send });
  };

  const shown = openAsks(asks, now).filter((a) => !hidden.has(a.id));
  if (shown.length === 0) return null;
  const time = dateFormat("en-US", { timeZone, hour: "numeric", minute: "2-digit" });
  const day = dateFormat("en-US", { timeZone, weekday: "short" });
  const sameDay = dateFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" });

  return (
    <section aria-label="Waiting on you" className="mb-4 grid grid-cols-1 gap-4 lg:grid-cols-2">
      {shown.map((ask, i) => {
        const until = ask.expires_at ? new Date(ask.expires_at) : null;
        const heading = [
          ask.agent_name ? `${ask.agent_name} asks` : "A question",
          agoLabel(Date.parse(ask.created_at), now),
          until ? `until ${sameDay.format(until) === sameDay.format(new Date(now)) ? "" : `${day.format(until)} `}${time.format(until)}` : null,
        ]
          .filter(Boolean)
          .join(" · ");
        const tint = ask.agent_color ?? "var(--primary)";
        return (
          <Tile key={ask.id} index={i} label={ask.question} style={{ boxShadow: `inset 0 0 0 1px color-mix(in oklab, ${tint} 35%, transparent)` }}>
            <div className="flex h-full flex-col gap-4 p-5">
              <div className="flex items-start gap-3.5">
                <span
                  className="grid size-10 shrink-0 place-items-center rounded-full"
                  style={{ backgroundColor: `color-mix(in oklab, ${tint} 16%, transparent)`, color: tint }}
                  aria-hidden="true"
                >
                  <MessageCircleQuestionIcon className="size-5" />
                </span>
                <div className="min-w-0 flex-1">
                  <p className="text-xs font-bold tracking-[0.12em] text-muted-foreground uppercase">{heading}</p>
                  <h2 className="mt-1 text-lg leading-snug font-semibold text-balance">{ask.question}</h2>
                  {ask.detail ? <p className="mt-1 line-clamp-3 text-sm text-muted-foreground">{ask.detail}</p> : null}
                  {ask.url ? (
                    <a href={ask.url} target="_blank" rel="noreferrer" className="mt-1.5 inline-flex items-center gap-1.5 text-sm font-medium text-primary hover:underline">
                      <LinkIcon className="size-3.5" aria-hidden="true" />
                      {hostOf(ask.url)}
                    </a>
                  ) : null}
                </div>
              </div>
              <div className="mt-auto flex flex-wrap gap-2">
                {ask.choices.map((choice, c) => (
                  <Button key={choice} size="lg" variant={c === 0 ? "default" : "secondary"} className="h-10 rounded-full px-4" onClick={() => answer(ask, choice)}>
                    {choice}
                  </Button>
                ))}
              </div>
            </div>
          </Tile>
        );
      })}
    </section>
  );
}

function hostOf(url: string): string {
  try {
    return new URL(url).host.replace(/^www\./, "");
  } catch {
    return url;
  }
}
