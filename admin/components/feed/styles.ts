import type { CSSProperties } from "react";

// The feed layouts' shared look: big rounded cards on the canvas with a soft
// ring, a lift for the ones that open something, and a staggered rise when a
// list arrives.

// A card: the console's surface, rounder than shadcn's Card, ringed softly.
export const CARD = "rounded-[24px] bg-card text-card-foreground ring-1 ring-foreground/8";

// A card that opens something lifts 2 px with a soft shadow under it. Only
// translate and the shadow move (the ring is a box-shadow too); on the dark
// canvas the shadow has to be plain black, since no token is darker than it.
// The same lift as a linked StatTile.
export const LIFT =
  "transition-[translate,box-shadow] duration-300 ease-out hover:shadow-lg hover:shadow-foreground/10 hover:ring-foreground/20 has-[a:focus-visible]:ring-2 has-[a:focus-visible]:ring-ring motion-safe:hover:-translate-y-0.5 dark:hover:shadow-black/50";

// A link that covers its whole card (the card is `relative`), so the card is
// one target without nesting links: anything else clickable on it sits above
// with `relative z-10`.
export const STRETCH = "outline-none after:absolute after:inset-0 after:rounded-[inherit] after:content-['']";

// The rise: .feed-rise (app/globals.css) with the item's place in the list.
// Capped so the last of a long list still starts within a third of a second.
export function rise(index: number): { className: string; style: CSSProperties } {
  return { className: "feed-rise", style: { "--i": Math.min(Math.max(0, index), 8) } as CSSProperties };
}
