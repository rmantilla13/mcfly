"use client";

import { cn } from "cn";
import { LayoutGridIcon, Rows3Icon } from "lucide-react";
import { type ReactNode, useState } from "react";

export type FeedView = "cards" | "manage";

// A feed tab as cards to look at, or as the table that edits it (hide,
// reorder, delete). Both are rendered on the server and handed over, so the
// switch is instant; the choice is kept in ?view=manage (without a
// navigation), so a reload or a saved form comes back to the same one.
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
  const option = (value: FeedView, label: string, Icon: typeof LayoutGridIcon) => (
    <button
      type="button"
      aria-pressed={view === value}
      onClick={() => change(value)}
      className={cn(
        "inline-flex h-7 items-center gap-1.5 rounded-md px-2.5 text-sm font-medium text-foreground/60 transition-[color,background-color,box-shadow] duration-200 outline-none hover:text-foreground focus-visible:ring-[3px] focus-visible:ring-ring/50 dark:text-muted-foreground dark:hover:text-foreground [&_svg]:size-4",
        view === value && "bg-background text-foreground shadow-sm dark:bg-input/30 dark:text-foreground",
      )}
    >
      <Icon aria-hidden="true" />
      {label}
    </button>
  );
  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-x-4 gap-y-3">
        <div className="min-w-0">{header}</div>
        <div className="inline-flex rounded-lg bg-muted p-[3px]" role="group" aria-label="View">
          {option("cards", "Cards", LayoutGridIcon)}
          {option("manage", "Manage", Rows3Icon)}
        </div>
      </div>
      {/* A fresh element per view, so the one coming in fades up. */}
      <div key={view} className="motion-safe:animate-in motion-safe:fade-in-0 motion-safe:slide-in-from-bottom-1 motion-safe:duration-300">
        {view === "cards" ? cards : manage}
      </div>
    </div>
  );
}
