import type { Metadata } from "next";
import { cookies } from "next/headers";
import { MoodProvider } from "@/components/MoodProvider";
import { AsksBand } from "@/components/today/AsksBand";
import { LayoutSwitch } from "@/components/today/LayoutSwitch";
import { TodayAssistant } from "@/components/today/TodayAssistant";
import { TodayBento } from "@/components/today/TodayBento";
import { TodayView } from "@/components/today/TodayView";
import { getSettings, listOpenAsks, requireAdmin } from "@/lib/data";
import { loadToday } from "@/lib/today-data";
import { TODAY_LAYOUT_COOKIE, todayLayout } from "@/lib/today-layout";

export const metadata: Metadata = { title: "Today" };

// The display's Home, on the web: refreshed by the page every minute. The
// mood (the glow's colours) follows the display's zone here, not the
// browser's, as on /ambient. Three layouts, as the display has: today,
// bento and assistant, picked with the switcher and remembered by this
// browser (lib/today-layout.ts). Over all three, what the agents are
// waiting on you to answer (AsksBand).
export default async function TodayPage() {
  await requireAdmin();
  const layout = todayLayout((await cookies()).get(TODAY_LAYOUT_COOKIE)?.value);
  // Who answers is said on the assistant's card.
  const [data, settings, asks] = await Promise.all([loadToday(), layout === "assistant" ? getSettings() : null, listOpenAsks()]);
  return (
    <>
      <MoodProvider timeZone={data.timeZone} />
      <div className="mb-4 flex justify-end">
        <LayoutSwitch current={layout} />
      </div>
      <AsksBand asks={asks} nowMs={data.nowMs} timeZone={data.timeZone} />
      {layout === "bento" ? (
        <TodayBento data={data} />
      ) : layout === "assistant" ? (
        <TodayAssistant data={data} provider={settings?.assistant_provider === "grok" ? "grok" : "claude"} />
      ) : (
        <TodayView data={data} />
      )}
    </>
  );
}
