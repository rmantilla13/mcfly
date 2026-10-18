import { askHistory } from "@/lib/ask-turns";
import { askAssistant, requireAdmin, type AskMode } from "@/lib/data";
import { DataError } from "@/lib/errors";

// Ask McFly from the console (Today's Ask bar, /voice, /ask): the browser
// posts here; this passes the question to the assistant edge function with
// the admin's own JWT (which never reaches the page) and streams the answer
// back unchanged.
export async function POST(req: Request) {
  await requireAdmin();
  const body = (await req.json().catch(() => null)) as { message?: unknown; history?: unknown; mode?: unknown } | null;
  const message = typeof body?.message === "string" ? body.message.trim().slice(0, 2000) : "";
  if (!message) return Response.json({ error: "Ask something first." }, { status: 400 });
  const history = askHistory(body?.history);
  try {
    const mode: AskMode = body?.mode === "quick" || body?.mode === "read" ? body.mode : "chat";
    let upstream = await askAssistant(message, history, mode);
    // A function deployed before "read" existed refuses the mode with a 400:
    // answer in chat mode rather than not at all until it's redeployed.
    if (upstream.status === 400 && mode === "read") {
      await upstream.body?.cancel();
      upstream = await askAssistant(message, history, "chat");
    }
    if (!upstream.ok || !upstream.body) {
      const err = (await upstream.json().catch(() => null)) as { error?: string } | null;
      return Response.json({ error: err?.error ?? "McFly couldn't answer just now." }, { status: 502 });
    }
    return new Response(upstream.body, { headers: { "Content-Type": "text/event-stream", "Cache-Control": "no-store" } });
  } catch (err) {
    return Response.json({ error: err instanceof DataError ? err.message : "McFly couldn't answer just now." }, { status: 500 });
  }
}
