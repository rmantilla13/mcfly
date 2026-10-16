import type { Metadata } from "next";
import { VoiceScreen } from "@/components/voice/VoiceScreen";
import { requireAdmin } from "@/lib/data";
import { loadToday } from "@/lib/today-data";

export const metadata: Metadata = { title: "Talk to McFly" };

// Full screen, outside the console's shell, like /ambient. The questions it
// offers are Today's, built from what's on the display.
export default async function VoicePage() {
  await requireAdmin();
  const data = await loadToday();
  return <VoiceScreen suggestions={data.suggestions} />;
}
