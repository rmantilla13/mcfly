import type { Metadata } from "next";
import { claimDeviceAction, renameDeviceAction, revokeDeviceAction } from "@/app/(console)/actions";
import { DevicesTable } from "@/components/DevicesTable";
import { PageHeader } from "@/components/PageHeader";
import { PairForm } from "@/components/PairForm";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { listDevices, requireAdmin } from "@/lib/data";
import { isOnline, plural } from "@/lib/format";

export const metadata: Metadata = { title: "Displays" };

export default async function DisplaysPage() {
  await requireAdmin();
  const devices = await listDevices();
  const online = devices.filter((d) => isOnline(d.last_seen_at)).length;

  return (
    <>
      <PageHeader title="Displays" subtitle="The screens paired to McFly. Each one reads the feeds as its own device user." />
      <div className="grid grid-cols-[minmax(0,1.7fr)_minmax(0,1fr)] items-start gap-5 max-xl:grid-cols-1">
        <Card className="gap-0 py-0">
          <CardHeader className="border-b py-4">
            <CardTitle>Paired displays</CardTitle>
            <CardDescription>
              {plural(devices.length, "display")} · {online} online (seen in the last 15 minutes)
            </CardDescription>
          </CardHeader>
          <CardContent className="px-0 pt-2 pb-2">
            <DevicesTable devices={devices} renameAction={renameDeviceAction} revokeAction={revokeDeviceAction} />
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Pair a display</CardTitle>
            <CardDescription>An unpaired display shows a QR code and a 6-digit code. Enter the code here, or scan the QR code with a signed-in phone.</CardDescription>
          </CardHeader>
          <CardContent>
            <PairForm action={claimDeviceAction} />
          </CardContent>
        </Card>
      </div>
    </>
  );
}
