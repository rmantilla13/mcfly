import { cn } from "cn";
import { MessageCircleQuestionIcon } from "lucide-react";
import Link from "next/link";
import { AskPanel } from "./AskPanel";
import { DayDigest } from "./DayDigest";
import { Tile, TileHead } from "./Tile";

// Asking McFly from Today: the day in a few sentences (on demand), the
// questions this page suggests (lib/suggestions.ts, from what is on it;
// each opens the full-screen Ask with it asked), and the Ask bar itself.
// "Summarize my day" is the digest's own button, so the chips are built
// without it (TodayView) and the four are four others.

export function AskTile({ day, timeZone, suggestions: chips, index, className }: { day: string; timeZone: string; suggestions: string[]; index: number; className?: string }) {
  return (
    <Tile index={index} label="Ask McFly" className={cn("gap-4 p-5", className)}>
      <TileHead icon={<MessageCircleQuestionIcon />}>Ask McFly</TileHead>
      {/* A new day, a new digest: keyed so yesterday's answer doesn't linger. */}
      <DayDigest key={day} day={day} timeZone={timeZone} />
      {chips.length ? (
        <ul className="flex flex-wrap gap-2" aria-label="Suggested questions">
          {chips.map((q) => (
            <li key={q} className="min-w-0">
              <Link
                href={`/ask?q=${encodeURIComponent(q)}`}
                className="flex h-9 max-w-full items-center rounded-full bg-card px-3.5 text-[13px] font-medium text-foreground no-underline ring-1 ring-foreground/10 transition-colors outline-none hover:bg-accent hover:text-accent-foreground hover:ring-transparent focus-visible:ring-2 focus-visible:ring-ring"
              >
                <span className="truncate">{q}</span>
              </Link>
            </li>
          ))}
        </ul>
      ) : null}
      <div className="mt-auto">
        <AskPanel />
      </div>
    </Tile>
  );
}
