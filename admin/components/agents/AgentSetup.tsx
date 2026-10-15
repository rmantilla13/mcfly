"use client";

import { CheckCircle2Icon, KeyRoundIcon, LoaderIcon, SendIcon } from "lucide-react";
import { useEffect, useState } from "react";
import { agentLastSeenAction } from "@/app/(console)/actions";
import { CopyButton } from "@/components/CopyButton";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { curlExample, exampleBody, ingestUrl } from "@/lib/curl";
import { agentPrompt, type AgentTemplate } from "@/lib/templates";
import type { AgentScope } from "@/lib/types";

// Right after an agent is made: its key (shown once), the task prompt to
// paste into the AI that runs it, the curl, a test push from this browser,
// and a live "waiting for the first push" that turns green when it lands.
// The key stays in this component's state; nothing stores it.
export function AgentSetup({
  agentId,
  name,
  template,
  scopes,
  apiKey,
  baseUrl,
  demo,
}: {
  agentId: string;
  name: string;
  template: AgentTemplate;
  scopes: AgentScope[];
  apiKey: string;
  baseUrl: string;
  demo: boolean;
}) {
  const [seen, setSeen] = useState<string | null>(null);
  const [test, setTest] = useState<{ state: "idle" | "sending" | "ok" | "error"; message?: string }>({ state: "idle" });
  const prompt = agentPrompt({ template, name, baseUrl, key: apiKey, scopes });
  const curl = curlExample({ baseUrl, key: apiKey, kind: template.kind, feed: template.feed });

  // Poll until the first push shows up.
  useEffect(() => {
    if (seen) return;
    let stop = false;
    const check = async () => {
      const at = await agentLastSeenAction(agentId).catch(() => null);
      if (!stop && at) setSeen(at);
    };
    const id = setInterval(check, 4000);
    void check();
    return () => {
      stop = true;
      clearInterval(id);
    };
  }, [agentId, seen]);

  // The test push goes straight from this browser to the ingest function.
  async function sendTest() {
    setTest({ state: "sending" });
    try {
      const res = await fetch(ingestUrl(baseUrl, template.feed), {
        method: "POST",
        headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
        body: exampleBody(template.feed),
      });
      const body = (await res.json().catch(() => ({}))) as { ok?: boolean; error?: string; count?: number };
      if (res.ok && body.ok) setTest({ state: "ok", message: `Pushed ${body.count ?? 1} to ${template.feed}. It's on the display now.` });
      else setTest({ state: "error", message: body.error ?? `The push failed (${res.status}).` });
    } catch {
      setTest({ state: "error", message: "Couldn't reach McFly from this browser." });
    }
  }

  return (
    <Card className="ring-primary/30">
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <KeyRoundIcon className="size-4 text-primary" />
          Set up {name}
        </CardTitle>
        <CardDescription>Give the AI that runs it the prompt below. The key is inside it; it is shown only now.</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center gap-3 rounded-lg bg-muted px-3 py-2.5">
          <code className="font-mono text-sm font-semibold tracking-wide break-all select-all">{apiKey}</code>
          <CopyButton text={apiKey} label="Copy key" ariaLabel="Copy the key" />
        </div>
        <Alert variant="destructive">
          <AlertTitle>This key is shown once.</AlertTitle>
          <AlertDescription>Copy the prompt or the key before you leave this page; only a rotation makes a new one.</AlertDescription>
        </Alert>

        <Tabs defaultValue="prompt">
          <TabsList>
            <TabsTrigger value="prompt">Task prompt</TabsTrigger>
            <TabsTrigger value="curl">curl</TabsTrigger>
          </TabsList>
          <TabsContent value="prompt" className="flex flex-col gap-2">
            <div className="flex items-center justify-between gap-3">
              <span className="text-sm text-muted-foreground">Paste into a scheduled Grok task, a Claude routine or your script&apos;s notes.</span>
              <CopyButton text={prompt} label="Copy prompt" ariaLabel="Copy the task prompt" />
            </div>
            <pre className="max-h-80 overflow-auto rounded-lg bg-muted px-3 py-2.5 font-mono text-xs leading-relaxed whitespace-pre-wrap">{prompt}</pre>
          </TabsContent>
          <TabsContent value="curl" className="flex flex-col gap-2">
            <div className="flex justify-end">
              <CopyButton text={curl} label="Copy curl" ariaLabel="Copy the curl example" />
            </div>
            <pre className="overflow-x-auto rounded-lg bg-muted px-3 py-2.5 font-mono text-xs leading-relaxed whitespace-pre">{curl}</pre>
          </TabsContent>
        </Tabs>

        <div className="flex flex-wrap items-center gap-3 rounded-xl border px-4 py-3">
          {seen ? (
            <span className="flex items-center gap-2 text-sm font-medium text-success">
              <CheckCircle2Icon className="size-4" /> First push received. {name} is live.
            </span>
          ) : (
            <span className="flex items-center gap-2 text-sm text-muted-foreground">
              <LoaderIcon className="size-4 animate-spin motion-reduce:animate-none" /> Waiting for {name}&apos;s first push…
            </span>
          )}
          <span className="flex-1" />
          <Button variant="outline" size="sm" onClick={sendTest} disabled={test.state === "sending" || demo}>
            <SendIcon data-icon="inline-start" />
            {test.state === "sending" ? "Sending…" : "Send a test push"}
          </Button>
        </div>
        {demo ? <p className="text-xs text-muted-foreground">Test pushes are off in demo mode; there is no McFly to push to.</p> : null}
        {test.message ? (
          <p className={test.state === "ok" ? "text-sm text-success" : "text-sm text-destructive"}>{test.message}</p>
        ) : null}
      </CardContent>
    </Card>
  );
}
