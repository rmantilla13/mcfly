import type { Metadata } from "next";
import {
  createAgentAction,
  deleteAgentAction,
  revokeAgentAction,
  rotateAgentKeyAction,
  updateAgentAction,
} from "@/app/(console)/actions";
import { AgentsTable } from "@/components/AgentsTable";
import { NewAgentForm } from "@/components/NewAgentForm";
import { PageHeader } from "@/components/PageHeader";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { isDemo, listAgents, requireAdmin } from "@/lib/data";
import { supabaseProjectUrl } from "@/lib/env";
import { plural } from "@/lib/format";

export const metadata: Metadata = { title: "Agents" };

// Where the curl example points. Demo mode has no project; the placeholder
// makes that obvious in the pasted command.
const PLACEHOLDER_URL = "https://your-project.supabase.co";

export default async function AgentsPage() {
  await requireAdmin();
  const agents = await listAgents();
  const baseUrl = supabaseProjectUrl() ?? PLACEHOLDER_URL;

  return (
    <>
      <PageHeader title="Agents" subtitle="Who pushes to McFly, with the key each one uses. A key is shown once, when it is made." />
      <div className="flex flex-col gap-5">
        <Card>
          <CardHeader>
            <CardTitle>New agent</CardTitle>
            <CardDescription>Pick what it&apos;s for, then paste the prompt it gives you into the AI that runs it.</CardDescription>
          </CardHeader>
          <CardContent>
            <NewAgentForm action={createAgentAction} baseUrl={baseUrl} demo={await isDemo()} />
          </CardContent>
        </Card>

        <Card className="gap-0 py-0">
          <CardHeader className="border-b py-4">
            <CardTitle>All agents</CardTitle>
            <CardDescription>{plural(agents.length, "agent")} · revoked ones are listed last</CardDescription>
          </CardHeader>
          <CardContent className="px-0 pt-4 pb-2">
            <AgentsTable
              agents={agents}
              baseUrl={baseUrl}
              actions={{
                rotate: rotateAgentKeyAction,
                update: updateAgentAction,
                revoke: revokeAgentAction,
                remove: deleteAgentAction,
              }}
            />
          </CardContent>
        </Card>
      </div>
    </>
  );
}
