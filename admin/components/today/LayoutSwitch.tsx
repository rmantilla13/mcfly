"use client";

import { cn } from "cn";
import { LayoutGridIcon, ListIcon, SparklesIcon, type LucideIcon } from "lucide-react";
import { useRouter } from "next/navigation";
import { useOptimistic, useRef, useTransition, type KeyboardEvent } from "react";
import { TODAY_LAYOUT_COOKIE, TODAY_LAYOUTS, type TodayLayout } from "@/lib/today-layout";

// Today, Bento or Assistant (lib/today-layout.ts): a radio group, so the
// arrow keys move the choice and Tab leaves it. Picking one remembers it in
// this browser's cookie and asks the server for the page again; the button
// shows the pick at once (optimistically, until the page arrives). Phone-
// sized targets on a phone.

// For a year; the page reads it on the server.
function remember(layout: TodayLayout) {
  document.cookie = `${TODAY_LAYOUT_COOKIE}=${layout}; path=/; max-age=31536000; samesite=lax`;
}

const OPTIONS: Record<TodayLayout, { label: string; icon: LucideIcon }> = {
  today: { label: "Today", icon: ListIcon },
  bento: { label: "Bento", icon: LayoutGridIcon },
  assistant: { label: "Assistant", icon: SparklesIcon },
};

export function LayoutSwitch({ current }: { current: TodayLayout }) {
  const router = useRouter();
  const [, startTransition] = useTransition();
  const [picked, setPicked] = useOptimistic(current);
  const buttons = useRef<(HTMLButtonElement | null)[]>([]);

  const pick = (layout: TodayLayout) => {
    if (layout === picked) return;
    remember(layout);
    startTransition(() => {
      setPicked(layout);
      router.refresh();
    });
  };

  const onKey = (e: KeyboardEvent, i: number) => {
    const step = e.key === "ArrowRight" || e.key === "ArrowDown" ? 1 : e.key === "ArrowLeft" || e.key === "ArrowUp" ? -1 : 0;
    if (!step) return;
    e.preventDefault();
    const j = (i + step + TODAY_LAYOUTS.length) % TODAY_LAYOUTS.length;
    buttons.current[j]?.focus();
    pick(TODAY_LAYOUTS[j]);
  };

  return (
    <div role="radiogroup" aria-label="Layout" className="inline-flex rounded-full bg-muted p-1 ring-1 ring-foreground/[0.06]">
      {TODAY_LAYOUTS.map((layout, i) => {
        const { label, icon: Icon } = OPTIONS[layout];
        const on = layout === picked;
        return (
          <button
            key={layout}
            ref={(el) => {
              buttons.current[i] = el;
            }}
            type="button"
            role="radio"
            aria-checked={on}
            tabIndex={on ? 0 : -1}
            onClick={() => pick(layout)}
            onKeyDown={(e) => onKey(e, i)}
            className={cn(
              "flex h-11 items-center gap-1.5 rounded-full px-3.5 text-[13px] font-medium transition-colors outline-none focus-visible:ring-2 focus-visible:ring-ring sm:h-9",
              on ? "bg-card text-foreground shadow-sm ring-1 ring-foreground/10" : "text-muted-foreground hover:text-foreground",
            )}
          >
            <Icon className="size-4" aria-hidden="true" />
            {label}
          </button>
        );
      })}
    </div>
  );
}
