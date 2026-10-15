import type { Metadata } from "next";
import {
  addCalendarSourceAction,
  deleteCalendarSourceAction,
  syncCalendarSourceAction,
  updateCalendarSourceAction,
} from "@/app/(console)/actions";
import { CalendarSources } from "@/components/CalendarSources";
import { PageHeader } from "@/components/PageHeader";
import { listCalendarSources, requireAdmin } from "@/lib/data";

export const metadata: Metadata = { title: "Calendars" };

export default async function CalendarsPage() {
  await requireAdmin();
  const sources = await listCalendarSources();
  return (
    <>
      <PageHeader
        title="Calendars"
        subtitle="Subscribe to Google, iCloud or Outlook calendars. McFly reads them every 15 minutes; agents you allow can read them too."
      />
      <CalendarSources
        sources={sources}
        actions={{ add: addCalendarSourceAction, update: updateCalendarSourceAction, remove: deleteCalendarSourceAction, sync: syncCalendarSourceAction }}
      />
    </>
  );
}
