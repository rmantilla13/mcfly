"use client";

import { LayoutGridIcon, ListIcon, Rows3Icon } from "lucide-react";
import { type ReactNode, useState } from "react";
import RubberSegment from "@/components/reactbits/RubberSegment";

export type FeedView = "cards" | "list" | "manage";

// A feed tab as cards to look at, or as the table that edits it (hide,
// reorder, delete), and for a tab that has one (Projects), as a list in
// between. All are rendered on the server and handed over, so the switch is
// instant; the choice is kept in ?view=list or ?view=manage (without a
// navigation), so a reload or a saved form comes back to the same one. The
// control is React Bits' RubberSegment: the thumb stretches across to the
// other choice and squashes into place, and can be dragged or flicked.
const CARDS = { value: "cards", label: "Cards", icon: <LayoutGridIcon className="size-4" aria-hidden="true" /> };
const LIST = { value: "list", label: "List", icon: <ListIcon className="size-4" aria-hidden="true" /> };
const MANAGE = { value: "manage", label: "Manage", icon: <Rows3Icon className="size-4" aria-hidden="true" /> };

export function ViewSwitch({
  initial,
  header,
  cards,
  list,
  manage,
}: {
  initial: FeedView;
  header: ReactNode;
  cards: ReactNode;
  list?: ReactNode;
  manage: ReactNode;
}) {
  const hasList = list !== undefined;
  // ?view= as this tab reads it: a list only where there is one.
  const read = (v: string | null): FeedView => (v === "manage" || (v === "list" && hasList) ? v : "cards");
  // The server's choice while rendering there and hydrating (it read the
  // same URL); a tab opened later follows the URL as it is by then, which
  // FeedTabs clears on every switch.
  const [view, setView] = useState<FeedView>(() => (typeof window === "undefined" ? read(initial) : read(new URL(window.location.href).searchParams.get("view"))));
  const change = (next: FeedView) => {
    if (next === view) return;
    setView(next);
    const url = new URL(window.location.href);
    if (next === "cards") url.searchParams.delete("view");
    else url.searchParams.set("view", next);
    window.history.replaceState(window.history.state, "", url);
  };
  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-x-4 gap-y-3">
        <div className="min-w-0">{header}</div>
        <RubberSegment
          aria-label="View"
          items={hasList ? [CARDS, LIST, MANAGE] : [CARDS, MANAGE]}
          value={view}
          onChange={(next) => change(next as FeedView)}
          size="md"
          radius={10}
          trackColor="var(--muted)"
          thumbColor="var(--view-thumb)"
          textColor="var(--foreground)"
          activeTextColor="var(--foreground)"
          className="[--view-thumb:var(--card)] dark:[--view-thumb:var(--input)]"
        />
      </div>
      {/* A fresh element per view, so the one coming in fades up. */}
      <div key={view} className="motion-safe:animate-in motion-safe:fade-in-0 motion-safe:slide-in-from-bottom-1 motion-safe:duration-300">
        {view === "cards" ? cards : view === "list" ? list : manage}
      </div>
    </div>
  );
}
