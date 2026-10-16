import { cn } from "cn";
import { BotIcon } from "lucide-react";
import Link from "next/link";
import type { CSSProperties } from "react";
import { EmptyState } from "@/components/bits";
import { StatusDot } from "@/components/charts";
import { agentBeat, cadenceLabel } from "@/lib/feed-layout";
import { formatNumber } from "@/lib/format";
import { agoLabel } from "@/lib/insights";
import type { AgentRow, IngestEntry } from "@/lib/types";

// Every agent as a chip: its colour as a dot, which breathes while the agent
// is pushing on its usual rhythm (lib/feed-layout.ts agentBeat), its last
// push and how often it usually comes. One silent for over a week turns
// amber and says so; a revoked one is greyed out. The dots breathe out of
// step with each other, so a row of them never pulses in unison.

const PHASES = ["0s", "-0.7s", "-1.5s", "-0.3s", "-1.1s", "-1.9s"];

export function AgentsRoster({ agents, pushes, now }: { agents: AgentRow[]; pushes: IngestEntry[]; now: number }) {
  if (agents.length === 0) {
    return (
      <EmptyState title="No agents yet" icon={<BotIcon />}>
        Create one under Agents; it gets a key to push with.
      </EmptyState>
    );
  }
  // Each agent's landed pushes in the log, with their feed, for its rhythm.
  const times = new Map<string, { at: number; feed: string }[]>();
  for (const e of pushes) {
    if (e.status !== "ok" || !e.agent_id) continue;
    const at = Date.parse(e.created_at);
    if (!Number.isFinite(at)) continue;
    const list = times.get(e.agent_id);
    if (list) list.push({ at, feed: e.feed });
    else times.set(e.agent_id, [{ at, feed: e.feed }]);
  }
  return (
    <ul className="flex flex-wrap gap-2">
      {agents.map((a, i) => {
        const beat = agentBeat(a, times.get(a.id) ?? [], now);
        const every = cadenceLabel(beat.cadence);
        const when =
          beat.state === "revoked" ? "revoked" : beat.state === "never" ? "no push yet" : beat.last !== null ? agoLabel(beat.last, now) : "";
        // Only live and quiet claim anything about its rhythm.
        const status =
          beat.state === "live" ? "pushing on its usual rhythm" : beat.state === "quiet" ? "quiet for over a week" : beat.state === "ok" ? "" : when;
        return (
          <li key={a.id}>
            <Link
              href="/agents"
              className={cn(
                "group/chip inline-flex h-10 items-center gap-2.5 rounded-full bg-card py-1 pr-4 pl-3.5 text-sm no-underline ring-1 ring-foreground/8 transition-[background-color,box-shadow] duration-200 outline-none hover:bg-accent/60 hover:ring-foreground/15 focus-visible:ring-2 focus-visible:ring-ring",
                beat.state === "revoked" && "opacity-60",
              )}
              style={{ "--phase": PHASES[i % PHASES.length] } as CSSProperties}
              aria-label={`${a.name}${status ? `: ${status}` : ""}${beat.state !== "revoked" && beat.last !== null ? `, last push ${when}` : ""}${every && beat.state !== "revoked" ? `, usually ${every}` : ""}`}
            >
              <StatusDot
                state={beat.state === "quiet" ? "warn" : beat.state === "live" || beat.state === "ok" ? "ok" : "unknown"}
                color={beat.state === "live" || beat.state === "ok" ? a.color : null}
                pulse={beat.state === "live"}
                // The breath's phase, per chip: an inherited variable, set
                // as important so it outranks the module's shorthand.
                className="after:[animation-delay:var(--phase)]!"
              />
              <span className="font-medium text-foreground">{a.name}</span>
              <span className={cn("text-[13px] whitespace-nowrap text-muted-foreground", beat.state === "quiet" && "font-medium text-warning")}>
                {beat.state === "quiet" ? `quiet · ${when}` : when}
                {every && beat.state !== "revoked" ? ` · ${every}` : ""}
              </span>
              {a.pushes_7d ? (
                <span className="rounded-full bg-foreground/6 px-1.5 text-xs text-muted-foreground tabular-nums max-sm:hidden" title="Pushes in the last 7 days">
                  {formatNumber(a.pushes_7d)}
                </span>
              ) : null}
            </Link>
          </li>
        );
      })}
    </ul>
  );
}
