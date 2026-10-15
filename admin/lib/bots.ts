// Grok bot helpers for the console: starter bots and schedule wording. Pure,
// so tests/bots.test.mjs can check it.

import type { AgentScope, BotOutput } from "./types.ts";

export type BotStarter = {
  id: string;
  label: string;
  name: string;
  color: string;
  prompt: string;
  output: BotOutput;
  every_minutes: number;
  at_minute: number | null;
  web_search: boolean;
  x_search: boolean;
  scopes: AgentScope[];
};

export const BOT_STARTERS: BotStarter[] = [
  {
    id: "morning",
    label: "Morning briefing",
    name: "Morning brief",
    color: "#7A64E8",
    prompt:
      "Brief me on what matters today: the markets before the open, the AI and tech news worth knowing, and what's on my calendar. Three short sections, the most important thing first.",
    output: "brief",
    every_minutes: 1440,
    at_minute: 7 * 60,
    web_search: true,
    x_search: true,
    scopes: ["memory:read", "calendar:read"],
  },
  {
    id: "hourly",
    label: "Hourly check-in",
    name: "Hourly",
    color: "#5B7CF5",
    prompt: "What changed in the last hour that I should know about? Markets, breaking news, and what people on X are saying about the topics I follow. Say \"Quiet hour\" if nothing did.",
    output: "brief",
    every_minutes: 60,
    at_minute: 8 * 60,
    web_search: true,
    x_search: true,
    scopes: ["memory:read"],
  },
  {
    id: "pulse",
    label: "Daily Pulse report",
    name: "Daily Pulse",
    color: "#E2725B",
    prompt:
      "Write today's Daily Pulse: the most important stories in AI & tech, markets, social media and the creator economy, each with a one-line takeaway and its source link. Pick one top story.",
    output: "news",
    every_minutes: 1440,
    at_minute: 6 * 60,
    web_search: true,
    x_search: true,
    scopes: ["memory:read"],
  },
  {
    id: "x",
    label: "What X is saying",
    name: "X watch",
    color: "#1D1B24",
    prompt: "Search X for the conversations about the companies, people and topics I follow. Summarize the 3 to 5 that matter, with links to the posts.",
    output: "brief",
    every_minutes: 180,
    at_minute: 8 * 60,
    web_search: false,
    x_search: true,
    scopes: ["memory:read"],
  },
];

export const SCHEDULES: { minutes: number; label: string }[] = [
  { minutes: 15, label: "Every 15 minutes" },
  { minutes: 30, label: "Every 30 minutes" },
  { minutes: 60, label: "Every hour" },
  { minutes: 180, label: "Every 3 hours" },
  { minutes: 360, label: "Every 6 hours" },
  { minutes: 720, label: "Twice a day" },
  { minutes: 1440, label: "Once a day" },
];

function clock(minute: number): string {
  const h = Math.floor(minute / 60);
  const m = minute % 60;
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}:${String(m).padStart(2, "0")} ${h < 12 ? "AM" : "PM"}`;
}

export function scheduleLabel(every: number, at: number | null): string {
  if (every >= 1440) return at == null ? "Once a day" : `Daily at ${clock(at)}`;
  const base = SCHEDULES.find((s) => s.minutes === every)?.label ?? `Every ${every} minutes`;
  return at == null ? base : `${base}, from ${clock(at)}`;
}
