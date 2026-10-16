import type { Metadata } from "next";
import { AskScreen } from "@/components/ask/AskScreen";
import { requireAdmin } from "@/lib/data";
import { loadToday } from "@/lib/today-data";

export const metadata: Metadata = { title: "Ask McFly" };

// Full screen, outside the console's shell, like /voice and /ambient: the
// assistant in read mode, with room for a long answer. The suggested
// questions are Today's, built from what's on the display. ?q= is a question
// to ask on arrival (Today's "Ask about this").
export default async function AskPage({ searchParams }: { searchParams: Promise<{ q?: string | string[] }> }) {
  await requireAdmin();
  const [data, params] = await Promise.all([loadToday(), searchParams]);
  const q = typeof params.q === "string" ? params.q.trim().slice(0, 2000) : "";
  return <AskScreen suggestions={data.suggestions} question={q || undefined} />;
}
