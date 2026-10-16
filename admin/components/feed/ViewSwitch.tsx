"use client";

import { LayoutGridIcon, Rows3Icon } from "lucide-react";
import { type ReactNode, useState } from "react";
import RubberSegment from "@/components/reactbits/RubberSegment";

export type FeedView = "cards" | "manage";

// A feed tab as cards to look at, or as the table that edits it (hide,
// reorder, delete). Both are rendered on the server and handed over, so the
// switch is instant; the choice is kept in ?view=manage (without a
// navigation), so a reload or a saved form comes back to the same one. The
// control is React Bits' RubberSegment: the thumb stretches across to the
// other choice and squashes into place, and can be dragged or flicked.
const VIEWS = [
  { value: "cards", label: "Cards", icon: <LayoutGridIcon className="size-4" aria-hidden="true" /> },
  { value: "manage", label: "Manage", icon: <Rows3Icon className="size-4" aria-hidden="true" /> },
];

export function ViewSwitch({ initial, header, cards, manage }: { initial: FeedView; header: ReactNode; cards: ReactNode; manage: ReactNode }) {
  // The server's choice while rendering there and hydrating (it read the
  // same URL); a tab opened later follows the URL as it is by then, which
  // FeedTabs clears on every switch.
  const [view, setView] = useState<FeedView>(() =>
    typeof window === "undefined" ? initial : new URL(window.location.href).searchParams.get("view") === "manage" ? "manage" : "cards",
  );
  const change = (next: FeedView) => {
    if (next === view) return;
    setView(next);
    const url = new URL(window.location.href);
    if (next === "manage") url.searchParams.set("view", "manage");
    else url.searchParams.delete("view");
    window.history.replaceState(window.history.state, "", url);
  };
  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-x-4 gap-y-3">
        <div className="min-w-0">{header}</div>
        <RubberSegment
          aria-label="View"
          items={VIEWS}
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
        {view === "cards" ? cards : manage}
      </div>
    </div>
  );
}
