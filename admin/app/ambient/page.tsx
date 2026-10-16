import type { Metadata } from "next";
import { MoodProvider } from "@/components/MoodProvider";
import { AmbientView } from "@/components/today/AmbientView";
import { requireAdmin } from "@/lib/data";
import { loadToday } from "@/lib/today-data";

export const metadata: Metadata = { title: "Ambient" };

// Full screen, outside the console's shell: the display's screen saver for a
// spare monitor or a tablet. Same admin check as every console page. The
// mood (the glow's colours) follows the display's zone here, not the
// browser's.
export default async function AmbientPage() {
  await requireAdmin();
  const data = await loadToday();
  return (
    <>
      <MoodProvider timeZone={data.timeZone} />
      <AmbientView data={data} />
    </>
  );
}
