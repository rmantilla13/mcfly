import type { CSSProperties } from "react";
import { cssColor } from "@/lib/format";

// What colour a chart draws in. Charts paint with currentColor, so a tone is
// just a text colour token: up is success, down destructive, neutral the
// brand blue, warn the amber. An agent's own colour wins when it is a real
// colour (cssColor), so a sparkline can wear the colour of the agent that
// pushed it.
export type ChartTone = "up" | "down" | "neutral" | "warn";

const TONE_CLASS: Record<ChartTone, string> = {
  up: "text-success",
  down: "text-destructive",
  neutral: "text-primary",
  warn: "text-warning",
};

export function toneProps(tone: ChartTone = "neutral", color?: string | null): { className: string; style?: CSSProperties } {
  const safe = cssColor(color);
  return safe ? { className: "", style: { color: safe } } : { className: TONE_CLASS[tone] ?? TONE_CLASS.neutral };
}
