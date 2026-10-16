import { cn } from "cn";
import { ExternalLinkIcon } from "lucide-react";
import type { CSSProperties } from "react";
import { CARD, LIFT, rise, STRETCH } from "@/components/feed/styles";
import type { NewsItem } from "@/lib/types";

// One Daily Pulse story, as the display's StoryCard draws it: the picture
// (or a tile in the section's colour with its initial), the section on it,
// then the headline, the takeaway and where it's from. The whole card opens
// the story at its source.

export function StoryCard({ item, color, index = 0 }: { item: NewsItem; color: string; index?: number }) {
  const r = rise(index);
  return (
    <article className={cn(CARD, LIFT, "group/story relative flex flex-col overflow-hidden", r.className)} style={r.style}>
      <div className="relative aspect-[16/9] overflow-hidden bg-muted" style={{ "--tint": color } as CSSProperties}>
        {item.image_url ? (
          // Agents send any https URL; a plain img keeps it off the image
          // optimizer and sends no referrer to the source.
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={item.image_url}
            alt=""
            loading="lazy"
            referrerPolicy="no-referrer"
            className="absolute inset-0 size-full object-cover transition-transform duration-700 ease-out motion-safe:group-hover/story:scale-[1.03]"
          />
        ) : (
          <SectionTile name={item.section_name} />
        )}
        <SectionTag name={item.section_name} />
      </div>
      <div className="flex flex-1 flex-col gap-1.5 p-4">
        <h3 className="leading-snug font-semibold text-pretty">
          <a href={item.url} target="_blank" rel="noopener noreferrer" className={cn(STRETCH, "text-foreground no-underline")}>
            {item.headline}
          </a>
        </h3>
        {item.takeaway ? <p className="line-clamp-3 text-[13px] text-muted-foreground">{item.takeaway}</p> : null}
        <span className="mt-auto inline-flex items-center gap-1 pt-1.5 text-xs text-muted-foreground">
          {item.source_domain ?? hostOf(item.url)}
          <ExternalLinkIcon className="size-3" aria-hidden="true" />
        </span>
      </div>
    </article>
  );
}

// No picture: the section's colour as a soft diagonal (.feed-tint, from
// --tint on the parent) with its initial, like the display's tiles.
export function SectionTile({ name, className }: { name: string; className?: string }) {
  return (
    <div className={cn("feed-tint absolute inset-0 grid place-items-center", className)} aria-hidden="true">
      <span className="font-heading text-[64px] leading-none font-bold text-white/75 select-none [text-shadow:0_1px_18px_rgb(0_0_0/0.12)]">{(name || "·").slice(0, 1).toUpperCase()}</span>
    </div>
  );
}

// The section's name over the picture.
export function SectionTag({ name }: { name: string }) {
  return (
    <span className="absolute top-3 left-3 rounded-full bg-black/45 px-2.5 py-1 text-[11px] font-semibold tracking-wider text-white uppercase backdrop-blur-sm">
      {name}
    </span>
  );
}

function hostOf(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return url;
  }
}
