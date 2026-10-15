import { KeyRoundIcon } from "lucide-react";
import { CopyButton } from "@/components/CopyButton";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { curlExample, feedNote } from "@/lib/curl";
import type { AgentKind } from "@/lib/types";

// The one time an agent's key is on screen: after it is made or rotated.
// Nothing stores the key; the backend keeps only its hash.
export function KeyReveal({
  agentName,
  kind,
  apiKey,
  baseUrl,
}: {
  agentName: string;
  kind: AgentKind;
  apiKey: string;
  baseUrl: string;
}) {
  const example = curlExample({ baseUrl, key: apiKey, kind });
  const note = feedNote(kind);
  return (
    <Card className="ring-primary/30">
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <KeyRoundIcon className="size-4 text-primary" />
          Key for {agentName}
        </CardTitle>
        <CardDescription>Give it to the agent now. Rotating the key replaces it.</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center gap-3 rounded-lg bg-muted px-3 py-2.5">
          <code className="font-mono text-sm font-semibold tracking-wide break-all select-all">{apiKey}</code>
          <CopyButton text={apiKey} label="Copy key" ariaLabel="Copy the key" />
        </div>
        <Alert variant="destructive">
          <AlertTitle>This key is shown once.</AlertTitle>
          <AlertDescription>Close or reload this page and it is gone for good; only a rotation makes a new one.</AlertDescription>
        </Alert>
        <div className="flex flex-col gap-2">
          <div className="flex items-center justify-between gap-3">
            <span className="text-sm font-medium">Try it</span>
            <CopyButton text={example} label="Copy curl" ariaLabel="Copy the curl example" />
          </div>
          <pre className="overflow-x-auto rounded-lg bg-muted px-3 py-2.5 font-mono text-xs leading-relaxed whitespace-pre">{example}</pre>
          {note ? <p className="text-xs text-muted-foreground">{note}</p> : null}
        </div>
      </CardContent>
    </Card>
  );
}
