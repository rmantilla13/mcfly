import { cn } from "cn";
import Link from "next/link";
import type { CSSProperties, ReactNode } from "react";
import { Spotlight } from "@/components/reactbits/SpotlightCard";
import styles from "./today.module.css";

// The Today page's tiles: big rounded cards with a soft ring, rising into
// place one after another (`index` sets the stagger). TodayView places them
// on its grid with the spans it passes in `className`. A tile with an `href`
// is one link and lifts a little under the pointer, as the Overview's
// StatTiles do (no token is darker than the dark canvas, so the shadow there
// is plain black). A tile with more than one thing to press keeps its links
// inside instead: links can't nest.
//
// Every tile is lit by React Bits' Spotlight: a soft light under the pointer
// that catches the tile's edge, reaches a tile the pointer is near, flares
// on a press and settles on whatever has the keyboard's focus. It is the
// page's ink at the original's strengths for each scheme — faint on the
// light cards, a glow on the dark ones — and it is still until the pointer
// moves.

const TILE =
  "relative isolate flex min-w-0 flex-col rounded-[26px] bg-card text-card-foreground ring-1 ring-foreground/[0.06] [--spotlight-fill:0.28] [--spotlight-rim:0.7] dark:[--spotlight-fill:1] dark:[--spotlight-rim:1]";
const LIFT =
  "no-underline outline-none transition-[translate,box-shadow] duration-300 ease-out hover:shadow-lg hover:shadow-foreground/10 hover:ring-foreground/15 focus-visible:ring-2 focus-visible:ring-ring motion-safe:hover:-translate-y-0.5 dark:hover:shadow-black/50";

export function Tile({
  index = 0,
  label,
  href,
  className,
  style,
  children,
}: {
  index?: number;
  label?: string; // names a plain tile for screen readers (a link is named by what it says)
  href?: string;
  className?: string;
  style?: CSSProperties;
  children: ReactNode;
}) {
  const props = { className: cn(TILE, styles.rise, href && LIFT, className), style: { ...style, "--i": index } as CSSProperties };
  return href ? (
    <Link href={href} {...props}>
      <Spotlight />
      {children}
    </Link>
  ) : (
    <section aria-label={label} {...props}>
      <Spotlight />
      {children}
    </section>
  );
}

// A tile's kicker: small caps, a glyph, and something on the right.
export function TileHead({ icon, children, action, className }: { icon?: ReactNode; children: ReactNode; action?: ReactNode; className?: string }) {
  return (
    <div className={cn("flex min-h-7 items-center gap-2", className)}>
      {icon ? (
        <span className="flex text-muted-foreground [&_svg]:size-4" aria-hidden="true">
          {icon}
        </span>
      ) : null}
      <h2 className="text-xs font-bold tracking-[0.12em] text-muted-foreground uppercase">{children}</h2>
      {action ? <div className="ml-auto flex items-center gap-1">{action}</div> : null}
    </div>
  );
}
