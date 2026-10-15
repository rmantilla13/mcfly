import type { Metadata } from "next";
import Link from "next/link";
import { claimDeviceAction } from "@/app/(console)/actions";
import { PageHeader } from "@/components/PageHeader";
import { PairForm } from "@/components/PairForm";
import { readString } from "@/components/bits";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { requireAdmin } from "@/lib/data";
import { sanitizeCode } from "@/lib/pairing";

export const metadata: Metadata = { title: "Pair a display" };

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

// What a display's QR code opens: https://mcfly.bot/pair?code=123456. The
// proxy sends a signed-out visitor through /login?next=/pair?code=… and
// back; by the time this renders the caller is an admin. The code is
// reduced to its digits before anything shows it.
export default async function PairPage({ searchParams }: Props) {
  await requireAdmin();
  const code = sanitizeCode(readString((await searchParams).code));

  return (
    <>
      <PageHeader
        title="Pair a display"
        subtitle={code ? "The code from the display's QR code is filled in. Give the screen a name and pair it." : "Enter the 6-digit code the display shows."}
        actions={
          <Button variant="outline" asChild>
            <Link href="/displays">All displays</Link>
          </Button>
        }
      />
      <Card className="max-w-xl">
        <CardHeader>
          <CardTitle>Claim the display</CardTitle>
          <CardDescription>The display polls for its session every 3 seconds and switches to the feeds once it is claimed.</CardDescription>
        </CardHeader>
        <CardContent>
          <PairForm action={claimDeviceAction} initialCode={code} autoFocus />
        </CardContent>
      </Card>
    </>
  );
}
