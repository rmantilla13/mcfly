import type { Metadata } from "next";
import { TodayView } from "@/components/today/TodayView";
import { requireAdmin } from "@/lib/data";
import { loadToday } from "@/lib/today-data";

export const metadata: Metadata = { title: "Today" };

// The display's Home, on the web: refreshed by the page every minute.
export default async function TodayPage() {
  await requireAdmin();
  return <TodayView data={await loadToday()} />;
}
