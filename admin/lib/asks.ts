// Questions agents are waiting on (the asks table, migration 20261029000010):
// two to four choices, the first the main one, answered on any screen with
// answer_ask. The display and the app show the same open ones. Pure, so
// tests/asks.test.mjs can check it.

export type OpenAsk = {
  id: string;
  question: string;
  detail: string | null;
  choices: string[];
  url: string | null;
  expires_at: string | null;
  created_at: string;
  agent_name: string | null;
  agent_color: string | null;
};

// The ones still waiting at `nowMs`, oldest first: one that has run out, or
// has fewer than two choices, is left out.
export function openAsks(rows: OpenAsk[], nowMs: number): OpenAsk[] {
  return rows
    .filter((a) => a.choices.length >= 2 && (a.expires_at == null || Date.parse(a.expires_at) > nowMs))
    .sort((a, b) => a.created_at.localeCompare(b.created_at));
}

// The choice another screen got in first, from answer_ask's refusal
// ("already answered: Hold"), or null for any other error.
export function answeredElsewhere(message: string): string | null {
  const m = /already answered: (.+?)\.?$/i.exec(message.trim());
  return m ? m[1].trim() : null;
}

// What the demo asks: the display's two (display/resources/demo/feed.json),
// from whichever agents fit.
export function demoAsks(agents: { id: string; name: string; kind: string; color: string }[], nowMs: number): OpenAsk[] {
  const code = agents.find((a) => a.kind === "other") ?? agents[0];
  const news = agents.find((a) => a.kind === "news") ?? agents[0];
  const at = (minutes: number) => new Date(nowMs + minutes * 60_000).toISOString();
  return [
    {
      id: "a5c00000-0000-0000-0000-000000000001",
      question: "Ship McFly v2.3 to TestFlight?",
      detail: "CI is green on main and the release notes are in the PR.",
      choices: ["Ship it", "Hold"],
      url: "https://github.com/rmantilla13/mcfly/pull/40",
      expires_at: at(6 * 60),
      created_at: at(-95),
      agent_name: code?.name ?? null,
      agent_color: code?.color ?? null,
    },
    {
      id: "a5c00000-0000-0000-0000-000000000002",
      question: "Which story leads tomorrow's Pulse?",
      detail: null,
      choices: ["Chips", "Rates", "Launch"],
      url: null,
      expires_at: null,
      created_at: at(-12),
      agent_name: news?.name ?? null,
      agent_color: news?.color ?? null,
    },
  ];
}
