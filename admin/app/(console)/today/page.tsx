import type { Metadata } from "next";
import { MoodProvider } from "@/components/MoodProvider";
import { TodayView } from "@/components/today/TodayView";
import { requireAdmin } from "@/lib/data";
import { loadToday } from "@/lib/today-data";

export const metadata: Metadata = { title: "Today" };

// The display's Home, on the web: refreshed by the page every minute. The
// mood (the glow's colours) follows the display's zone here, not the
// browser's, as on /ambient.
export default async function TodayPage() {
  await requireAdmin();
  const data = await loadToday();
  return (
    <>
      <MoodProvider timeZone={data.timeZone} />
      <TodayView data={data} />
    </>
  );
}
