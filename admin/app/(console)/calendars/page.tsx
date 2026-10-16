import type { Metadata } from "next";
import { Suspense } from "react";
import {
  addCalendarSourceAction,
  connectGoogleAction,
  deleteCalendarSourceAction,
  disconnectGoogleAccountAction,
  syncCalendarSourceAction,
  toggleGoogleCalendarAction,
  updateCalendarSourceAction,
} from "@/app/(console)/actions";
import { CalendarSources } from "@/components/CalendarSources";
import { GoogleCalendars, type GoogleAccountView } from "@/components/GoogleCalendars";
import { PageHeader } from "@/components/PageHeader";
import { Skeleton } from "@/components/ui/skeleton";
import { listCalendarSources, listGoogleAccounts, listGoogleCalendars, requireAdmin } from "@/lib/data";
import { googleCalendarRows, googleNotice, type GoogleNotice } from "@/lib/google-calendars";
import type { CalendarSource, GoogleAccount } from "@/lib/types";

export const metadata: Metadata = { title: "Calendars" };

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

// Two ways in: sign in to Google and switch calendars on, or paste an iCal
// link. Google's redirect lands back here with ?google=connected or
// ?google_error=…, which the Google section turns into a toast.
export default async function CalendarsPage({ searchParams }: Props) {
  await requireAdmin();
  // The accounts are asked for alongside the sources, but the section that
  // needs Google's own answers streams in after the rest of the page.
  const accounts = listGoogleAccounts();
  accounts.catch(() => {}); // handled where it is awaited, in GoogleSection
  const [sources, params] = await Promise.all([listCalendarSources(), searchParams]);
  return (
    <>
      <PageHeader
        title="Calendars"
        subtitle="Sign in to Google and pick calendars, or paste an iCal link. McFly reads them every 15 minutes, read-only; agents you allow can read them too."
      />
      <div className="flex flex-col gap-10">
        <Suspense fallback={<GooglePending />}>
          <GoogleSection accounts={accounts} sources={sources} notice={googleNotice(params)} />
        </Suspense>
        <CalendarSources
          sources={sources.filter((s) => s.kind !== "google")}
          actions={{ add: addCalendarSourceAction, update: updateCalendarSourceAction, remove: deleteCalendarSourceAction, sync: syncCalendarSourceAction }}
        />
      </div>
    </>
  );
}

// Each account's list comes from Google itself (one call per account).
async function GoogleSection({ accounts, sources, notice }: { accounts: Promise<GoogleAccount[]>; sources: CalendarSource[]; notice: GoogleNotice | null }) {
  const list = await accounts;
  const lists = await Promise.all(list.map((a) => listGoogleCalendars(a.id)));
  const views: GoogleAccountView[] = list.map((account, i) => {
    const got = lists[i];
    return {
      account,
      rows: googleCalendarRows(account, "calendars" in got ? got.calendars : null, sources),
      error: "error" in got ? got.error : null,
    };
  });
  return (
    <GoogleCalendars
      accounts={views}
      notice={notice}
      actions={{ connect: connectGoogleAction, toggle: toggleGoogleCalendarAction, disconnect: disconnectGoogleAccountAction, sync: syncCalendarSourceAction }}
    />
  );
}

function GooglePending() {
  return (
    <section className="flex flex-col gap-4" aria-busy="true" aria-labelledby="google-calendars-pending">
      <div>
        <h2 id="google-calendars-pending" className="font-heading text-lg font-semibold">
          Google Calendar
        </h2>
        <p className="mt-0.5 text-sm text-muted-foreground">Asking Google for your calendars…</p>
      </div>
      <Skeleton className="h-24 w-full rounded-2xl" />
    </section>
  );
}
