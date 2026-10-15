import type { Metadata } from "next";
import { deleteMemoryAction, saveMemoryAction } from "@/app/(console)/actions";
import { MemoryList } from "@/components/MemoryList";
import { PageHeader } from "@/components/PageHeader";
import { listAgents, listMemories, requireAdmin } from "@/lib/data";

export const metadata: Metadata = { title: "Memory" };

export default async function MemoryPage() {
  await requireAdmin();
  const [notes, agents] = await Promise.all([listMemories(), listAgents()]);
  return (
    <>
      <PageHeader
        title="Memory"
        subtitle="What McFly knows about you. The assistant reads these notes, and so do agents you let read memory. The display shows them too."
      />
      <MemoryList
        notes={notes}
        agents={agents.filter((a) => !a.revoked_at).map((a) => ({ id: a.id, name: a.name }))}
        actions={{ save: saveMemoryAction, remove: deleteMemoryAction }}
      />
    </>
  );
}
