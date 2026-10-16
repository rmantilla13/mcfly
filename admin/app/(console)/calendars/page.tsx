import type { Metadata } from "next";
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
import { listCalendarSources, listGoogleAccounts, listGoogleCalendars, requireAdmin } from "@/lib/data";
import { googleCalendarRows, googleNotice } from "@/lib/google-calendars";

export const metadata: Metadata = { title: "Calendars" };

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

// Two ways in: sign in to Google and switch calendars on, or paste an iCal
// link. Google's redirect lands back here with ?google=connected or
// ?google_error=…, which the Google section turns into a toast.
export default async function CalendarsPage({ searchParams }: Props) {
  await requireAdmin();
  const [sources, accounts, params] = await Promise.all([listCalendarSources(), listGoogleAccounts(), searchParams]);
  // Each account's list comes from Google itself (one call per account).
  const lists = await Promise.all(accounts.map((a) => listGoogleCalendars(a.id)));
  const views: GoogleAccountView[] = accounts.map((account, i) => {
    const got = lists[i];
    return {
      account,
      rows: googleCalendarRows(account, "calendars" in got ? got.calendars : null, sources),
      error: "error" in got ? got.error : null,
    };
  });
  return (
    <>
      <PageHeader
        title="Calendars"
        subtitle="Sign in to Google and pick calendars, or paste an iCal link. McFly reads them every 15 minutes, read-only; agents you allow can read them too."
      />
      <div className="flex flex-col gap-10">
        <GoogleCalendars
          accounts={views}
          notice={googleNotice(params)}
          actions={{ connect: connectGoogleAction, toggle: toggleGoogleCalendarAction, disconnect: disconnectGoogleAccountAction, sync: syncCalendarSourceAction }}
        />
        <CalendarSources
          sources={sources.filter((s) => s.kind !== "google")}
          actions={{ add: addCalendarSourceAction, update: updateCalendarSourceAction, remove: deleteCalendarSourceAction, sync: syncCalendarSourceAction }}
        />
      </div>
    </>
  );
}
