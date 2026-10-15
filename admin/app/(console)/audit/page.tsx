import type { Metadata } from "next";
import { AuditTable } from "@/components/AuditTable";
import { PageHeader } from "@/components/PageHeader";
import { Pagination, pageHref, readPage } from "@/components/bits";
import { Card, CardContent } from "@/components/ui/card";
import { listAudit, requireAdmin } from "@/lib/data";

export const metadata: Metadata = { title: "Audit log" };

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

export default async function AuditPage({ searchParams }: Props) {
  await requireAdmin();
  const result = await listAudit(readPage((await searchParams).page));

  return (
    <>
      <PageHeader title="Audit log" subtitle="Every admin change, newest first: what was done, to what, by whom, and when (UTC)." />
      <Card className="gap-0 py-0">
        <CardContent className="px-0 pt-2">
          <AuditTable entries={result.rows} />
          <Pagination page={result.page} hasMore={result.hasMore} shown={result.rows.length} href={pageHref("/audit", {})} />
        </CardContent>
      </Card>
    </>
  );
}
