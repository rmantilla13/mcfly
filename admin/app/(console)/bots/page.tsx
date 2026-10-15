import type { Metadata } from "next";
import { deleteBotAction, runBotAction, saveBotAction, setBotEnabledAction } from "@/app/(console)/actions";
import { BotsPanel } from "@/components/BotsPanel";
import { PageHeader } from "@/components/PageHeader";
import { listBots, requireAdmin } from "@/lib/data";

export const metadata: Metadata = { title: "Grok bots" };

export default async function BotsPage() {
  await requireAdmin();
  const bots = await listBots();
  return (
    <>
      <PageHeader
        title="Grok bots"
        subtitle="Bots McFly runs for you. On each schedule it asks Grok, with web and X search, and puts the answer on the display as a brief or a Daily Pulse report."
      />
      <BotsPanel bots={bots} xaiReady={null} actions={{ save: saveBotAction, enable: setBotEnabledAction, remove: deleteBotAction, run: runBotAction }} />
    </>
  );
}
