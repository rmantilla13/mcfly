import { cn } from "cn";
import { MeshGradient } from "@/components/MeshGradient";
import { cssColor } from "@/lib/format";
import { stampLabel, type TodayBrief } from "@/lib/today";
import { Tile } from "./Tile";

// The newest brief: who wrote it and when (with the day, once it isn't
// today's), in the agent's colour, its title
// and its points (or its first paragraph when it has none). The agent's
// colour also moves softly behind the heading, the display's gradient
// fading into the card: the page's second and last WebGL tile.

export function BriefCard({
  brief,
  now,
  timeZone,
  index,
  className,
}: {
  brief: NonNullable<TodayBrief>;
  now: number;
  timeZone: string;
  index: number;
  className?: string;
}) {
  const color = cssColor(brief.color) ?? "#5B7CF5";
  return (
    <Tile href="/feed?tab=briefs" index={index} className={cn("overflow-hidden", className)}>
      <div
        className="pointer-events-none absolute inset-x-0 top-0 h-36 [mask-image:linear-gradient(to_bottom,black_30%,transparent)]"
        style={{ backgroundColor: `color-mix(in oklab, ${color} 18%, var(--card))` }}
        aria-hidden="true"
      >
        <MeshGradient className="absolute inset-0" baseColor={color} seed={5} maxFps={15} resolution={0.6} speed={0.8} />
      </div>
      <div className="relative flex flex-col gap-3 p-6 max-sm:p-5">
        <span className="text-xs font-bold tracking-[0.12em] uppercase" style={{ color }}>
          <span className="rounded-full bg-card/70 px-2 py-1 backdrop-blur-sm">
            {brief.agent} · {brief.kind} · {stampLabel(Date.parse(brief.publishedAt), now, timeZone)}
          </span>
        </span>
        <span className="mt-6 text-[22px] leading-tight font-semibold tracking-[-0.01em]">{brief.title}</span>
        {brief.bullets.length ? (
          <>
            {brief.summary && !brief.bullets.includes(brief.summary) ? <span className="text-[15px] text-muted-foreground">{brief.summary}</span> : null}
            <ul className="flex flex-col gap-2">
              {brief.bullets.map((b, i) => (
                <li key={i} className="flex gap-3 text-[15px] leading-snug">
                  <span className="mt-[7px] size-1.5 shrink-0 rounded-full" style={{ background: color }} aria-hidden="true" />
                  <span>{b}</span>
                </li>
              ))}
            </ul>
          </>
        ) : (
          <span className="line-clamp-4 text-[15px] leading-relaxed text-muted-foreground">{brief.summary}</span>
        )}
      </div>
    </Tile>
  );
}
