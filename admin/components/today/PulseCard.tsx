import { cn } from "cn";
import { NewspaperIcon } from "lucide-react";
import { cssColor } from "@/lib/format";
import type { TodayHero } from "@/lib/today";
import { Tile } from "./Tile";

// Today's Pulse, led by its hero story: the picture (or the source's colour
// where there is none), the headline and its takeaway. Goes to the report.

export function PulseCard({ hero, index, className }: { hero: NonNullable<TodayHero>; index: number; className?: string }) {
  const color = cssColor(hero.color) ?? "#5B7CF5";
  return (
    <Tile href={`/feed/news/${hero.reportId}`} index={index} className={cn("group overflow-hidden", className)}>
      <div className="relative h-36 shrink-0 overflow-hidden" style={{ backgroundColor: `color-mix(in oklab, ${color} 20%, var(--card))` }}>
        {hero.imageUrl ? (
          // Pictures come from the agents' feeds, on any host; next/image would need each one allowed.
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={hero.imageUrl}
            alt=""
            className="size-full object-cover transition-[scale] duration-700 ease-out motion-safe:group-hover:scale-[1.03]"
          />
        ) : (
          <div
            className="grid size-full place-items-center"
            style={{ backgroundImage: `linear-gradient(135deg in oklab, color-mix(in oklab, ${color} 34%, var(--card)), color-mix(in oklab, ${color} 10%, var(--card)))`, color }}
            aria-hidden="true"
          >
            <NewspaperIcon className="size-9 opacity-70" />
          </div>
        )}
      </div>
      <div className="flex flex-col gap-1.5 p-5">
        <span className="text-xs font-bold tracking-[0.12em] uppercase" style={{ color }}>
          {hero.source} · {hero.count === 1 ? "1 story" : `${hero.count} stories`}
        </span>
        <span className="line-clamp-3 text-xl leading-snug font-semibold tracking-[-0.01em]">{hero.headline}</span>
        {hero.takeaway ? <span className="line-clamp-3 text-[15px] leading-snug text-muted-foreground">{hero.takeaway}</span> : null}
      </div>
    </Tile>
  );
}
