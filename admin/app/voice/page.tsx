import type { Metadata } from "next";
import { VoiceScreen } from "@/components/voice/VoiceScreen";
import { requireAdmin } from "@/lib/data";

export const metadata: Metadata = { title: "Talk to McFly" };

// Full screen, outside the console's shell, like /ambient.
export default async function VoicePage() {
  await requireAdmin();
  return <VoiceScreen />;
}
