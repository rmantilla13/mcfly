import { ChevronLeftIcon, ExternalLinkIcon, Trash2Icon } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { deleteNewsReportAction } from "@/app/(console)/actions";
import { ConfirmAction } from "@/components/ConfirmAction";
import { PageHeader } from "@/components/PageHeader";
import { Time } from "@/components/bits";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { getNewsReport, requireAdmin } from "@/lib/data";
import { formatDate, formatNumber, formatShortDate } from "@/lib/format";
import type { NewsItem } from "@/lib/types";

type Props = { params: Promise<{ id: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const detail = await getNewsReport((await params).id);
  return { title: detail ? `${detail.report.display_date ?? detail.report.slug} · News` : "News report" };
}

export default async function NewsReportPage({ params }: Props) {
  await requireAdmin();
  const detail = await getNewsReport((await params).id);
  if (!detail) notFound();
  const { report, items } = detail;

  // Items grouped by section, in the order the agent sent them.
  const sections = new Map<string, { name: string; items: NewsItem[] }>();
  for (const item of items) {
    const section = sections.get(item.section_key) ?? { name: item.section_name, items: [] };
    section.items.push(item);
    sections.set(item.section_key, section);
  }

  return (
    <>
      <PageHeader
        eyebrow={
          <Link href="/feed?tab=news" className="inline-flex items-center gap-1 text-muted-foreground no-underline hover:text-foreground">
            <ChevronLeftIcon className="size-3.5" /> News
          </Link>
        }
        title={report.display_date ?? formatShortDate(report.report_date)}
        subtitle={
          <>
            <code className="font-mono">{report.slug}</code> · {formatNumber(items.length)} stories in {sections.size} sections · published{" "}
            <Time iso={report.published_at} /> ({formatDate(report.published_at)})
          </>
        }
        actions={
          <ConfirmAction
            action={deleteNewsReportAction}
            fields={{ report_id: report.id }}
            title={`Delete the ${report.slug} report?`}
            description="Its stories leave every display. The agent can push the report again."
            confirmLabel="Delete report"
            tone="danger"
            trigger={
              <Button variant="destructive">
                <Trash2Icon data-icon="inline-start" />
                Delete report
              </Button>
            }
          />
        }
      />

      <div className="flex flex-col gap-5">
        {[...sections.entries()].map(([key, section]) => (
          <Card key={key}>
            <CardHeader>
              <CardTitle>{section.name}</CardTitle>
              <CardDescription>
                <code className="font-mono">{key}</code> · {formatNumber(section.items.length)} stories
              </CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col">
              {section.items.map((item, i) => (
                <div key={item.id}>
                  {i > 0 ? <Separator className="my-4" /> : null}
                  <article className="flex gap-4">
                    {item.image_url ? (
                      // Agents send any https URL; a plain img keeps it off the
                      // image optimizer and sends no referrer to the source.
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={item.image_url}
                        alt=""
                        width={112}
                        height={70}
                        loading="lazy"
                        referrerPolicy="no-referrer"
                        className="h-[70px] w-28 shrink-0 rounded-lg bg-muted object-cover"
                      />
                    ) : null}
                    <div className="flex min-w-0 flex-col gap-1">
                      <h3 className="font-medium leading-snug">
                        <a href={item.url} target="_blank" rel="noopener noreferrer" className="hover:underline">
                          {item.headline}
                        </a>
                        {report.hero_item === item.item_key ? (
                          <Badge variant="default" className="ml-2 align-middle">
                            Hero
                          </Badge>
                        ) : null}
                      </h3>
                      {item.takeaway ? <p className="text-sm text-muted-foreground">{item.takeaway}</p> : null}
                      <a
                        href={item.url}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
                      >
                        {item.source_domain ?? item.url}
                        <ExternalLinkIcon className="size-3" />
                      </a>
                    </div>
                  </article>
                </div>
              ))}
            </CardContent>
          </Card>
        ))}
      </div>
    </>
  );
}
