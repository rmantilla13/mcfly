"use client";

import { CalendarIcon, PlusIcon, RefreshCwIcon, Trash2Icon } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useId, useRef, useState, useTransition } from "react";
import { useFormStatus } from "react-dom";
import { toast } from "sonner";
import { ConfirmAction } from "@/components/ConfirmAction";
import { useFormAction } from "@/components/useFormAction";
import { EmptyState, Swatch, Time } from "@/components/bits";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Spinner } from "@/components/ui/spinner";
import { Switch } from "@/components/ui/switch";
import type { FormAction } from "@/lib/action-result";
import { plural } from "@/lib/format";
import type { GoogleCalendarRow, GoogleNotice } from "@/lib/google-calendars";
import type { GoogleAccount } from "@/lib/types";

// The Calendars page's Google section: sign in to a Google account once
// (read-only), and each of its calendars is a switch. What's on is a
// calendar subscription like a link's, read by calendar-sync through the
// Calendar API; the sign-in itself stays on the server (the google-calendar
// function), this page only ever sees the account's email.

export type GoogleAccountView = {
  account: GoogleAccount;
  rows: GoogleCalendarRow[];
  error: string | null; // why Google's list couldn't be read, if it couldn't
};

type ConnectAction = (formData: FormData) => Promise<void>;
type Actions = { connect: ConnectAction; toggle: FormAction; disconnect: FormAction; sync: FormAction };

export function GoogleCalendars({ accounts, notice, actions }: { accounts: GoogleAccountView[]; notice: GoogleNotice | null; actions: Actions }) {
  const router = useRouter();
  const told = useRef(false);
  // Back from Google: say how it went, then drop the query from the address.
  useEffect(() => {
    if (!notice || told.current) return;
    told.current = true;
    if (notice.kind === "connected") toast.success("Google account connected. Switch on the calendars to show.");
    else toast.error(notice.message.endsWith(".") ? notice.message : `${notice.message}.`);
    router.replace("/calendars", { scroll: false });
  }, [notice, router]);

  return (
    <section className="flex flex-col gap-4" aria-labelledby="google-calendars">
      <div className="flex flex-wrap items-end justify-between gap-x-6 gap-y-3">
        <div className="min-w-0">
          <h2 id="google-calendars" className="font-heading text-lg font-semibold">
            Google Calendar
          </h2>
          <p className="mt-0.5 text-sm text-muted-foreground">
            Sign in once, read-only, and switch on the calendars to show: your own, the ones shared with you, a work account&apos;s.
          </p>
        </div>
        <form action={actions.connect}>
          <ConnectButton>{accounts.length ? "Connect another account" : "Connect a Google account"}</ConnectButton>
        </form>
      </div>
      {accounts.length === 0 ? (
        <EmptyState title="No Google account yet" icon={<CalendarIcon />}>
          Connect one and its calendars appear here as switches. McFly reads them every 15 minutes and never changes them.
        </EmptyState>
      ) : (
        <ul className="flex flex-col gap-3">
          {accounts.map((view) => (
            <AccountCard key={view.account.id} view={view} actions={actions} />
          ))}
        </ul>
      )}
    </section>
  );
}

function ConnectButton({ children, variant = "default", size }: { children: string; variant?: "default" | "outline"; size?: "sm" }) {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" variant={variant} size={size} disabled={pending}>
      {pending ? <Spinner data-icon="inline-start" /> : <PlusIcon data-icon="inline-start" />}
      {pending ? "Going to Google…" : children}
    </Button>
  );
}

function AccountCard({ view, actions }: { view: GoogleAccountView; actions: Actions }) {
  const { account, rows } = view;
  const shown = rows.filter((r) => r.source).length;
  // One line about trouble: Google's answer just now, else what the last sync recorded.
  const trouble = view.error ?? account.last_error;
  return (
    <li className="rounded-2xl border bg-card">
      <div className="flex flex-wrap items-center gap-x-4 gap-y-2 px-4 py-3">
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <span className="truncate font-semibold">{account.email}</span>
            {trouble ? <Badge variant="warning">Needs a look</Badge> : null}
          </div>
          <div className="text-[13px] text-muted-foreground">
            connected <Time iso={account.connected_at} /> · {plural(shown, "calendar")} shown
          </div>
          {trouble ? <div className="text-[13px] text-destructive">{trouble}</div> : null}
        </div>
        <div className="flex items-center gap-1">
          {trouble ? (
            <form action={actions.connect}>
              <input type="hidden" name="email" value={account.email} />
              <ConnectButton variant="outline" size="sm">
                Connect again
              </ConnectButton>
            </form>
          ) : null}
          <ConfirmAction
            action={actions.disconnect}
            fields={{ account_id: account.id }}
            title={`Disconnect ${account.email}?`}
            description="Its calendars and their events leave the display, and Google forgets McFly. The calendars themselves are untouched."
            confirmLabel="Disconnect"
            tone="danger"
            trigger={
              <Button variant="ghost" size="icon-sm" aria-label={`Disconnect ${account.email}`}>
                <Trash2Icon />
              </Button>
            }
          />
        </div>
      </div>
      {rows.length ? (
        <ul className="divide-y border-t">
          {rows.map((row) => (
            <CalendarRow key={row.id} account={account} row={row} actions={actions} />
          ))}
        </ul>
      ) : view.error ? null : (
        <p className="border-t px-4 py-3 text-[13px] text-muted-foreground">Google lists no calendars for this account.</p>
      )}
    </li>
  );
}

function CalendarRow({ account, row, actions }: { account: GoogleAccount; row: GoogleCalendarRow; actions: Actions }) {
  const id = useId();
  const [pending, start] = useTransition();
  const [wanted, setWanted] = useState<boolean | null>(null); // what was just asked for, until the page catches up
  const [problem, setProblem] = useState<string | null>(null);
  const on = wanted ?? !!row.source;
  const sync = useFormAction(actions.sync, (res) => res?.ok && res.message && toast.success(res.message));

  const flip = (next: boolean) => {
    setWanted(next);
    start(async () => {
      const fd = new FormData();
      fd.set("account_id", account.id);
      fd.set("calendar_id", row.id);
      fd.set("name", row.name);
      if (row.color) fd.set("color", row.color);
      fd.set("on", String(next));
      if (row.source) fd.set("source_id", row.source.id);
      const res = await actions.toggle(null, fd);
      if (res?.ok) {
        setProblem(null);
        if (res.message) toast.success(res.message);
      } else {
        setProblem(res?.error ?? "Something went wrong. Try again.");
      }
      setWanted(null);
    });
  };

  // "live": Google notifies McFly of changes (row.live, judged on the
  // server); otherwise the calendar is read every 15 minutes.
  const status = row.source ? (
    <>
      {plural(row.source.event_count, "event")} ·{" "}
      {row.source.last_synced_at ? (
        <>
          synced <Time iso={row.source.last_synced_at} />
        </>
      ) : (
        "not read yet"
      )}
      {row.live ? <> · live</> : null}
    </>
  ) : row.access_role === "freeBusyReader" ? (
    "Free/busy only: Google shows no titles for it"
  ) : (
    "Not shown"
  );

  return (
    <li className="flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-2.5">
      <Swatch color={row.color} className="size-3.5" />
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-2">
          <label htmlFor={id} className="truncate font-medium">
            {row.name}
          </label>
          {row.primary ? <Badge variant="outline">Main calendar</Badge> : null}
          {!row.listed ? <Badge variant="warning">Not in Google&apos;s list anymore</Badge> : null}
          {row.source && !row.source.enabled ? <Badge variant="outline">Paused</Badge> : null}
        </div>
        <div className="text-[13px] text-muted-foreground">{status}</div>
        {row.source?.last_error ? <div className="text-[13px] text-destructive">{row.source.last_error}</div> : null}
        {row.source?.watch_error ? <div className="text-[13px] text-muted-foreground">Every 15 minutes, not live: {row.source.watch_error}</div> : null}
        {problem ? <div className="text-[13px] text-destructive">{problem}</div> : null}
        {sync.result && !sync.result.ok ? <div className="text-[13px] text-destructive">{sync.result.error}</div> : null}
      </div>
      {row.source ? (
        <form onSubmit={sync.submit}>
          <input type="hidden" name="source_id" value={row.source.id} />
          <Button type="submit" variant="ghost" size="icon-sm" aria-label={`Sync ${row.name} now`} disabled={sync.pending || !row.source.enabled}>
            {sync.pending ? <Spinner /> : <RefreshCwIcon />}
          </Button>
        </form>
      ) : null}
      {pending ? <Spinner className="size-4 text-muted-foreground" /> : null}
      <Switch id={id} checked={on} onCheckedChange={flip} disabled={pending} aria-label={`Show ${row.name}`} />
    </li>
  );
}
