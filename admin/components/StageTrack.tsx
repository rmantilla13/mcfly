import { cn } from "cn";
import { CheckIcon, OctagonAlertIcon, PauseIcon } from "lucide-react";
import type { CSSProperties } from "react";
import type { StageState, StageTrack } from "@/lib/feed-layout";

// A project's stages, drawn two ways. StageBar is the compact one for a list
// row or a card: the headline and the place ("Build · 2 of 4") over a bar
// with a segment per stage, the ones behind it filled in the project's
// colour and the one it is in standing taller (red while blocked, amber
// while paused). StageSteps is the project page's: a node per stage with its
// name, joined by a line, across on a wide screen and down on a phone.

const WORD: Record<StageState, string> = { done: "done", current: "now", blocked: "blocked", paused: "paused", next: "next" };

// The fill for a segment or node: the project's colour (or the brand blue)
// for done and current, the status colours for blocked and paused.
function fill(state: StageState, color: string | null): { className: string; style?: CSSProperties } {
  if (state === "blocked") return { className: "bg-destructive" };
  if (state === "paused") return { className: "bg-warning" };
  if (state === "next") return { className: "bg-foreground/10" };
  return color ? { className: "", style: { background: color } } : { className: "bg-primary" };
}

export function StageBar({ track, color, since, className }: { track: StageTrack; color: string | null; since?: string; className?: string }) {
  return (
    <div className={cn("flex min-w-0 flex-col gap-1.5", className)}>
      <div className="flex items-baseline justify-between gap-3 text-[13px] leading-tight">
        <span
          className={cn(
            "min-w-0 truncate font-medium",
            track.steps[track.index]?.state === "blocked" && "text-destructive",
            track.steps[track.index]?.state === "paused" && "text-warning",
          )}
        >
          {track.headline}
          {since ? <span className="font-normal text-muted-foreground"> · {since}</span> : null}
        </span>
        <span className="shrink-0 text-xs text-muted-foreground tabular-nums">{track.position}</span>
      </div>
      <ol className="flex h-2.5 items-center gap-1" aria-label={`Stages: ${track.headline}, ${track.position}`}>
        {track.steps.map((s, i) => {
          const f = fill(s.state, color);
          const here = i === track.index;
          return (
            <li
              key={s.name}
              title={`${s.name}: ${WORD[s.state]}`}
              className={cn(
                "feed-grow-x min-w-0 flex-1 origin-left rounded-full",
                here ? "h-2.5" : "h-1.5",
                s.state === "done" && "opacity-55",
                s.state === "blocked" && "motion-safe:animate-pulse",
                f.className,
              )}
              style={{ ...f.style, "--i": i } as CSSProperties}
            >
              <span className="sr-only">
                {s.name}, {WORD[s.state]}
              </span>
            </li>
          );
        })}
      </ol>
    </div>
  );
}

export function StageSteps({ track, color }: { track: StageTrack; color: string | null }) {
  const last = track.steps.length - 1;
  return (
    <ol className="flex flex-col sm:flex-row sm:overflow-x-auto sm:pb-1" aria-label={`Stages: ${track.headline}, ${track.position}`}>
      {track.steps.map((s, i) => {
        const f = fill(s.state, color);
        const reached = s.state !== "next";
        // The line on to the next stage: drawn in the colour once that one is reached too.
        const onward = i < last && track.steps[i + 1].state !== "next";
        const line = fill(onward ? "done" : "next", color);
        return (
          <li key={s.name} className="relative flex min-w-0 gap-3 pb-5 last:pb-0 sm:min-w-[96px] sm:flex-1 sm:flex-col sm:items-center sm:gap-2 sm:pb-0 sm:text-center">
            {i < last ? (
              <span
                aria-hidden="true"
                className={cn(
                  "absolute top-8 bottom-0 left-[15px] w-0.5 rounded-full sm:top-[15px] sm:right-[calc(-50%+20px)] sm:bottom-auto sm:left-[calc(50%+20px)] sm:h-0.5 sm:w-auto",
                  line.className,
                  onward && "opacity-55",
                )}
                style={line.style}
              />
            ) : null}
            <span
              aria-hidden="true"
              className={cn(
                "relative grid size-8 shrink-0 place-items-center rounded-full text-xs font-semibold tabular-nums",
                reached ? f.className : "bg-card text-muted-foreground ring-2 ring-foreground/12 ring-inset",
                s.state === "paused" ? "text-warning-foreground" : reached && "text-white",
                s.state === "done" && "opacity-80",
                s.state === "blocked" && "ring-4 ring-destructive/20",
                s.state === "paused" && "ring-4 ring-warning/25",
              )}
              style={
                s.state === "current"
                  ? { ...f.style, boxShadow: `0 0 0 4px color-mix(in oklab, ${color ?? "var(--primary)"} 22%, transparent)` }
                  : reached
                    ? f.style
                    : undefined
              }
            >
              {s.state === "done" ? (
                <CheckIcon className="size-4" strokeWidth={3} />
              ) : s.state === "blocked" ? (
                <OctagonAlertIcon className="size-4" />
              ) : s.state === "paused" ? (
                <PauseIcon className="size-4" />
              ) : s.state === "current" ? (
                <span className="size-2.5 rounded-full bg-white" />
              ) : (
                i + 1
              )}
            </span>
            <span className="flex min-w-0 flex-col pt-1 sm:pt-0">
              <span className={cn("text-sm leading-snug font-medium text-pretty", s.state === "next" && "text-muted-foreground")}>{s.name}</span>
              <span
                className={cn(
                  "text-xs text-muted-foreground",
                  s.state === "blocked" && "font-medium text-destructive",
                  s.state === "paused" && "font-medium text-warning",
                  s.state === "current" && "font-medium text-foreground",
                )}
              >
                {s.state === "next" ? `Stage ${i + 1}` : s.state === "done" ? "Done" : s.state === "current" ? "Now" : s.state === "blocked" ? "Blocked here" : "Paused here"}
              </span>
            </span>
          </li>
        );
      })}
    </ol>
  );
}
