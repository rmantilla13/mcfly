import { cn } from "cn";
import { ChevronLeftIcon, ExternalLinkIcon, Trash2Icon } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import type { CSSProperties } from "react";
import { deleteNewsReportAction } from "@/app/(console)/actions";
import { ConfirmAction } from "@/components/ConfirmAction";
import { MeshGradient } from "@/components/MeshGradient";
import { PageHeader } from "@/components/PageHeader";
import { SectionTag, StoryCard } from "@/components/StoryCard";
import { Time } from "@/components/bits";
import { AskLink } from "@/components/feed/bits";
import { CARD, rise, STRETCH } from "@/components/feed/styles";
import { Button } from "@/components/ui/button";
import { getNewsReport, requireAdmin } from "@/lib/data";
import { sectionColor } from "@/lib/feed-layout";
import { formatDate, formatNumber, formatShortDate, plural } from "@/lib/format";
import type { NewsItem } from "@/lib/types";

type Props = { params: Promise<{ id: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const detail = await getNewsReport((await params).id);
  return { title: detail ? `${detail.report.display_date ?? detail.report.slug} · News` : "News report" };
}

// A Daily Pulse report as a magazine: the lead story across the top (its
// picture, or a moving tile in its section's colour), then each section's
// other stories as cards, in the order the agent sent them. Section colours
// are the display's (lib/feed-layout.ts sectionColor).
export default async function NewsReportPage({ params }: Props) {
  await requireAdmin();
  const detail = await getNewsReport((await params).id);
  if (!detail) notFound();
  const { report, items } = detail;

  // Items grouped by section, in the order the agent sent them.
  const sections = new Map<string, { name: string; color: string; items: NewsItem[] }>();
  for (const item of [...items].sort((a, b) => a.section_order - b.section_order || a.position - b.position)) {
    const section = sections.get(item.section_key) ?? { name: item.section_name, color: sectionColor(item.section_key, sections.size), items: [] };
    section.items.push(item);
    sections.set(item.section_key, section);
  }
  const hero = items.find((i) => report.hero_item && i.item_key === report.hero_item) ?? sections.values().next().value?.items[0];
  const heroColor = hero ? (sections.get(hero.section_key)?.color ?? "#5B7CF5") : "#5B7CF5";
  // Each section without the lead, and the ones left with anything.
  const rest = [...sections.entries()]
    .map(([key, section]) => [key, { ...section, others: section.items.filter((item) => item.id !== hero?.id) }] as const)
    .filter(([, section]) => section.others.length > 0);
  const columns = rest.length > 1;
  let index = 1;

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

      <div className="flex flex-col gap-9">
        {hero ? (
          <article
            className={cn(CARD, "group/story relative grid grid-cols-1 overflow-hidden md:grid-cols-[minmax(0,1.15fr)_minmax(0,1fr)]", rise(0).className)}
            style={rise(0).style}
          >
            <div className="relative aspect-[16/10] overflow-hidden bg-muted md:aspect-auto md:min-h-[340px]" style={{ "--tint": heroColor } as CSSProperties}>
              {hero.image_url ? (
                // Agents send any https URL; a plain img keeps it off the image
                // optimizer and sends no referrer to the source.
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={hero.image_url}
                  alt=""
                  referrerPolicy="no-referrer"
                  className="absolute inset-0 size-full object-cover transition-transform duration-700 ease-out motion-safe:group-hover/story:scale-[1.02]"
                />
              ) : (
                // No picture: the section's colour, alive (the page's one
                // WebGL canvas), over the tint it shows without WebGL.
                <div className="feed-tint absolute inset-0">
                  <MeshGradient className="absolute inset-0" baseColor={heroColor} rings={1} seed={3} maxFps={15} resolution={0.75} />
                  <span
                    className="absolute inset-0 grid place-items-center font-heading text-[128px] leading-none font-bold text-white/75 select-none [text-shadow:0_2px_28px_rgb(0_0_0/0.14)]"
                    aria-hidden="true"
                  >
                    {hero.section_name.slice(0, 1).toUpperCase()}
                  </span>
                </div>
              )}
              <SectionTag name={hero.section_name} />
            </div>
            <div className="flex flex-col gap-3 p-7 max-sm:p-5">
              <span className="inline-flex items-center gap-2 text-xs font-semibold tracking-wider text-muted-foreground uppercase">
                <span className="size-2 rounded-full" style={{ background: heroColor }} aria-hidden="true" />
                The lead
              </span>
              <h2 className="font-heading text-[28px] leading-tight font-semibold tracking-tight text-balance max-sm:text-2xl">
                <a href={hero.url} target="_blank" rel="noopener noreferrer" className={cn(STRETCH, "text-foreground no-underline")}>
                  {hero.headline}
                </a>
              </h2>
              {hero.takeaway ? <p className="text-[16px] leading-relaxed text-muted-foreground">{hero.takeaway}</p> : null}
              <div className="mt-auto flex flex-wrap items-center gap-3 pt-2">
                <span className="inline-flex items-center gap-1 text-[13px] text-muted-foreground">
                  {hero.source_domain ?? hero.url}
                  <ExternalLinkIcon className="size-3" aria-hidden="true" />
                </span>
                <AskLink question={`What does "${hero.headline}" mean for me?`} label="Ask about this" />
              </div>
            </div>
          </article>
        ) : null}

        {/* The other stories: several sections side by side as columns, like
            a page of a paper; one section alone as a grid of its stories. */}
        <div className={cn("grid grid-cols-1 gap-x-5 gap-y-9", columns && "sm:grid-cols-2 lg:grid-cols-3")}>
          {rest.map(([key, section]) => (
            <section key={key} aria-label={section.name} className="flex min-w-0 flex-col gap-4">
              <h2 className="flex items-center gap-2.5 px-1">
                <span className="size-2.5 rounded-full" style={{ background: section.color }} aria-hidden="true" />
                <span className="font-heading text-lg font-semibold">{section.name}</span>
                <span className="text-sm text-muted-foreground">{plural(section.others.length, "story", "stories")}</span>
              </h2>
              <div className={cn("grid grid-cols-1 gap-4", !columns && "sm:grid-cols-2 lg:grid-cols-3")}>
                {section.others.map((item) => (
                  <StoryCard key={item.id} item={item} color={section.color} index={index++} />
                ))}
              </div>
            </section>
          ))}
        </div>
      </div>
    </>
  );
}
