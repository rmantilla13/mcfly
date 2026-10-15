import type { Metadata } from "next";
import { AmbientView } from "@/components/today/AmbientView";
import { requireAdmin } from "@/lib/data";
import { loadToday } from "@/lib/today-data";

export const metadata: Metadata = { title: "Ambient" };

// Full screen, outside the console's shell: the display's screen saver for a
// spare monitor or a tablet. Same admin check as every console page.
export default async function AmbientPage() {
  await requireAdmin();
  return <AmbientView data={await loadToday()} />;
}
