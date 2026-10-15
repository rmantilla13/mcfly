import { askAssistant, requireAdmin, type AskTurn } from "@/lib/data";
import { DataError } from "@/lib/errors";

// The Today page's Ask McFly: the browser posts here; this passes the
// question to the assistant edge function with the admin's own JWT (which
// never reaches the page) and streams the answer back unchanged.
export async function POST(req: Request) {
  await requireAdmin();
  const body = (await req.json().catch(() => null)) as { message?: unknown; history?: unknown; mode?: unknown } | null;
  const message = typeof body?.message === "string" ? body.message.trim().slice(0, 2000) : "";
  if (!message) return Response.json({ error: "Ask something first." }, { status: 400 });
  const history: AskTurn[] = Array.isArray(body?.history)
    ? body.history
        .filter((t): t is AskTurn => !!t && (t.role === "user" || t.role === "assistant") && typeof t.text === "string")
        .slice(-10)
        .map((t) => ({ role: t.role, text: t.text.slice(0, 4000) }))
    : [];
  try {
    const upstream = await askAssistant(message, history, body?.mode === "quick" ? "quick" : "chat");
    if (!upstream.ok || !upstream.body) {
      const err = (await upstream.json().catch(() => null)) as { error?: string } | null;
      return Response.json({ error: err?.error ?? "McFly couldn't answer just now." }, { status: 502 });
    }
    return new Response(upstream.body, { headers: { "Content-Type": "text/event-stream", "Cache-Control": "no-store" } });
  } catch (err) {
    return Response.json({ error: err instanceof DataError ? err.message : "McFly couldn't answer just now." }, { status: 500 });
  }
}
