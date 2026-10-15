import type { Metadata } from "next";
import { updateSettingsAction } from "@/app/(console)/actions";
import { BackendStatusCard } from "@/components/BackendStatusCard";
import { PageHeader } from "@/components/PageHeader";
import { SettingsForm } from "@/components/SettingsForm";
import { Time } from "@/components/bits";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { getBackendStatus, getSettings, requireAdmin } from "@/lib/data";

export const metadata: Metadata = { title: "Settings" };

export default async function SettingsPage() {
  await requireAdmin();
  const [settings, backend] = await Promise.all([getSettings(), getBackendStatus()]);

  return (
    <>
      <PageHeader title="Settings" subtitle="The display's name and clock, and how much of each feed is kept. Every change is written to the audit log." />
      <Card className="max-w-3xl">
        <CardHeader>
          <CardTitle>Platform</CardTitle>
          <CardDescription>
            {settings.updated_at ? (
              <>
                Last changed <Time iso={settings.updated_at} />
              </>
            ) : (
              "Never changed"
            )}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <SettingsForm action={updateSettingsAction} settings={settings} />
        </CardContent>
      </Card>
      <div className="mt-5">
        <BackendStatusCard status={backend} />
      </div>
    </>
  );
}
