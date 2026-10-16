"use client";

import { cn } from "cn";
import {
  BookOpenIcon,
  BotIcon,
  CalendarIcon,
  ChartSplineIcon,
  CornerDownLeftIcon,
  FolderKanbanIcon,
  GaugeIcon,
  LayoutDashboardIcon,
  LayoutGridIcon,
  MessageCircleQuestionIcon,
  MicIcon,
  MonitorIcon,
  MonitorPlayIcon,
  RssIcon,
  ScrollTextIcon,
  SearchIcon,
  SlidersHorizontalIcon,
  SparklesIcon,
  SunIcon,
} from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useId, useMemo, useRef, useState, useSyncExternalStore, type ComponentType, type KeyboardEvent as ReactKeyboardEvent } from "react";
import { commandIndexAction, type CommandIndex, type CommandKind } from "@/app/(console)/command-actions";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { FEED_TABS, type FeedTab } from "@/lib/feed-tabs";
import { matchScore } from "@/lib/suggestions";

// The command bar: ⌘K (Ctrl K) anywhere in the console, or the search field
// in the sidebar. Type to go to a page or a feed's tab, to find an agent, a
// project, a symbol, a metric, a dashboard or a bot by name, or to ask
// McFly (anything that reads as a question, or nothing else matched,
// leads with asking; it opens the full-screen Ask with it asked). Opened
// empty, it offers the pages and a few questions built from the feeds.
//
// The names come from the server (commandIndexAction) the first time it
// opens, so pages don't pay for it, and again on an open a few minutes
// later: the questions follow the clock (the next meeting, a fresh brief).
// A combobox over a listbox: arrows move, Enter opens, Escape closes.

type Icon = ComponentType<{ className?: string }>;
type Item = { id: string; label: string; hint?: string; href: string; Icon: Icon; color?: string | null };
type Section = { id: "go" | "find" | "ask"; title: string; items: Item[] };

// The sidebar's pages (components/NavLinks.tsx), and the full-screen ones.
const PAGES: Item[] = [
  { id: "page:today", label: "Today", href: "/today", Icon: SunIcon },
  { id: "page:overview", label: "Overview", href: "/", Icon: LayoutGridIcon },
  { id: "page:agents", label: "Agents", href: "/agents", Icon: BotIcon },
  { id: "page:bots", label: "Grok bots", href: "/bots", Icon: SparklesIcon },
  { id: "page:memory", label: "Memory", href: "/memory", Icon: BookOpenIcon },
  { id: "page:calendars", label: "Calendars", href: "/calendars", Icon: CalendarIcon },
  { id: "page:feed", label: "Feed", href: "/feed", Icon: RssIcon },
  { id: "page:displays", label: "Displays", href: "/displays", Icon: MonitorIcon },
  { id: "page:settings", label: "Settings", href: "/settings", Icon: SlidersHorizontalIcon },
  { id: "page:audit", label: "Audit log", href: "/audit", Icon: ScrollTextIcon },
  { id: "page:ambient", label: "Ambient view", hint: "Full screen", href: "/ambient", Icon: MonitorPlayIcon },
  { id: "page:ask", label: "Ask McFly", hint: "Full screen", href: "/ask", Icon: MessageCircleQuestionIcon },
  { id: "page:voice", label: "Talk to McFly", hint: "Voice", href: "/voice", Icon: MicIcon },
];

const EVERYDAY = new Set(["page:today", "page:overview", "page:feed", "page:agents", "page:bots", "page:calendars"]);

const TAB_LABEL: Record<FeedTab, string> = {
  briefs: "Briefs",
  markets: "Markets",
  news: "News",
  projects: "Projects",
  metrics: "Metrics",
  dashboards: "Dashboards",
  calendar: "Calendar",
};
const TABS: Item[] = FEED_TABS.map((t) => ({ id: `tab:${t}`, label: TAB_LABEL[t], hint: "Feed", href: `/feed?tab=${t}`, Icon: RssIcon }));

const KIND_ICON: Record<CommandKind, Icon> = {
  agent: BotIcon,
  project: FolderKanbanIcon,
  symbol: ChartSplineIcon,
  metric: GaugeIcon,
  dashboard: LayoutDashboardIcon,
  bot: SparklesIcon,
};

// Reads as a question: ends in "?" or starts the way questions do.
const QUESTION = /\?\s*$|^(what|why|how|when|who|where|which|is|are|was|were|should|can|could|do|does|did|will|would|any|tell|summar|explain|show me|give me)\b/i;

const askItem = (q: string, id = `ask:${q}`): Item => ({ id, label: q, href: `/ask?q=${encodeURIComponent(q)}`, Icon: SparklesIcon });

function rank<T>(query: string, list: T[], text: (t: T) => [string, string?], limit: number): T[] {
  return list
    .map((t, i) => {
      const [main, more] = text(t);
      return { t, i, s: Math.max(matchScore(query, main), more ? matchScore(query, more) * 0.8 : 0) };
    })
    .filter((x) => x.s > 0)
    .sort((a, b) => b.s - a.s || a.i - b.i)
    .slice(0, limit)
    .map((x) => x.t);
}

function sections(query: string, index: CommandIndex | null): Section[] {
  const q = query.trim();
  if (!q) {
    // Opened empty: the everyday pages (typing finds the rest) and a few
    // questions from the feeds.
    return [
      { id: "go", title: "Go to", items: PAGES.filter((p) => EVERYDAY.has(p.id)) },
      { id: "ask", title: "Try asking", items: (index?.questions ?? []).map((s) => askItem(s, `try:${s}`)) },
    ].filter((s) => s.items.length > 0) as Section[];
  }
  const go = rank(q, [...PAGES, ...TABS], (p) => [p.label, p.hint ? `${p.hint} ${p.label}` : undefined], 5);
  const find = rank(q, index?.entries ?? [], (e) => [e.label, e.hint], 8).map(
    (e): Item => ({ id: `${e.kind}:${e.id}`, label: e.label, hint: e.hint, href: e.href, Icon: KIND_ICON[e.kind], color: e.color }),
  );
  const ask = [
    { ...askItem(q), label: `Ask McFly “${q}”` },
    ...rank(q, index?.questions ?? [], (s) => [s], 2)
      .filter((s) => s !== q)
      .map((s) => askItem(s, `try:${s}`)),
  ];
  const all: Section[] = [
    { id: "go", title: "Go to", items: go },
    { id: "find", title: "In your feeds", items: find },
    { id: "ask", title: "Ask McFly", items: ask },
  ];
  // A question, or nothing else to go to: asking comes first.
  const askFirst = QUESTION.test(q) || (!go.length && !find.length);
  return (askFirst ? [all[2], all[0], all[1]] : all).filter((s) => s.items.length > 0);
}

const INDEX_TTL_MS = 5 * 60_000;

const noSubscribe = () => () => {};
const isMac = () => /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent);
const shortcut = () => (isMac() ? "⌘K" : "Ctrl K");

export function CommandBar() {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const [index, setIndex] = useState<CommandIndex | null>(null);
  const [loading, setLoading] = useState(false);
  const loadedAt = useRef(0);
  // The platform's own shortcut, once in the browser (none on the server).
  const keys = useSyncExternalStore(noSubscribe, shortcut, () => null);
  const listId = useId();

  const show = (next: boolean) => {
    setOpen(next);
    if (!next) return;
    setQuery("");
    setActive(0);
    // The first open reads the names; later ones reuse them for a few
    // minutes (showing the old ones while new ones load). A failed read
    // keeps what there was, and the next open tries again.
    if (!loading && Date.now() - loadedAt.current > INDEX_TTL_MS) {
      setLoading(true);
      commandIndexAction()
        .then(
          (next) => {
            setIndex(next);
            loadedAt.current = Date.now();
          },
          () => {},
        )
        .finally(() => setLoading(false));
    }
  };

  // ⌘K (Ctrl K off a Mac, where Ctrl K is a text field's own) from anywhere
  // in the console, to open it or close it; not over another dialog.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.defaultPrevented || e.altKey || e.shiftKey || e.key.toLowerCase() !== "k") return;
      if (!(isMac() ? e.metaKey && !e.ctrlKey : e.ctrlKey && !e.metaKey)) return;
      // Radix unmounts a closed dialog, so any other dialog here is open
      // (this one stays for its closing fade, and a quick ⌘K reopens it).
      if (!open && document.querySelector('[role="dialog"]:not([data-command-bar]), [role="alertdialog"]')) return;
      e.preventDefault();
      show(!open);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  const list = useMemo(() => sections(query, index), [query, index]);
  const items = list.flatMap((s) => s.items);
  const current = Math.min(active, Math.max(0, items.length - 1));
  const optionId = (n: number) => `${listId}-option-${n}`;

  // Keep the active option in view as the arrows move it.
  useEffect(() => {
    if (open) document.getElementById(optionId(current))?.scrollIntoView({ block: "nearest" });
  });

  const choose = (item: Item | undefined) => {
    if (!item) return;
    setOpen(false);
    router.push(item.href);
  };

  const onKeyDown = (e: ReactKeyboardEvent<HTMLInputElement>) => {
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      if (!items.length) return;
      const step = e.key === "ArrowDown" ? 1 : -1;
      setActive((current + step + items.length) % items.length);
    } else if (e.key === "Home" || e.key === "End") {
      e.preventDefault();
      setActive(e.key === "Home" ? 0 : items.length - 1);
    } else if (e.key === "Enter") {
      e.preventDefault();
      choose(items[current]);
    }
  };

  const q = query.trim();
  const nothing = !!q && !list.some((s) => s.id !== "ask");
  let n = 0; // option numbers run across the sections

  return (
    <>
      <button
        type="button"
        onClick={() => show(true)}
        className="flex h-10 w-full items-center gap-3 rounded-xl bg-sidebar-accent/60 px-3.5 text-[15px] text-muted-foreground ring-1 ring-sidebar-border transition-colors outline-none hover:bg-sidebar-accent hover:text-sidebar-accent-foreground focus-visible:ring-2 focus-visible:ring-sidebar-ring max-md:size-9 max-md:justify-center max-md:px-0"
        aria-label="Search or ask McFly"
        aria-keyshortcuts={keys ? (keys === "⌘K" ? "Meta+K" : "Control+K") : undefined}
      >
        <SearchIcon className="size-[18px] shrink-0" aria-hidden="true" />
        <span className="flex-1 text-left max-md:hidden">Search or ask</span>
        {keys ? (
          <kbd className="rounded-md bg-background px-1.5 py-0.5 font-sans text-[11px] font-medium text-muted-foreground ring-1 ring-border max-md:hidden">{keys}</kbd>
        ) : null}
      </button>

      <Dialog open={open} onOpenChange={show}>
        <DialogContent
          data-command-bar=""
          showCloseButton={false}
          aria-describedby={undefined}
          className="top-[12vh] max-w-[calc(100%-2rem)] translate-y-0 gap-0 overflow-hidden rounded-[22px] p-0 shadow-2xl ring-foreground/10 duration-150 sm:max-w-xl motion-reduce:animate-none!"
        >
          <DialogTitle className="sr-only">Search or ask McFly</DialogTitle>
          <div className="flex items-center gap-3 border-b px-4">
            <SearchIcon className="size-5 shrink-0 text-muted-foreground" aria-hidden="true" />
            <input
              autoFocus
              value={query}
              onChange={(e) => {
                setQuery(e.target.value);
                setActive(0);
              }}
              onKeyDown={onKeyDown}
              placeholder="Go to, find, or ask McFly…"
              role="combobox"
              aria-expanded="true"
              aria-controls={listId}
              aria-autocomplete="list"
              aria-activedescendant={items.length ? optionId(current) : undefined}
              aria-label="Search or ask McFly"
              maxLength={2000}
              className="h-14 min-w-0 flex-1 bg-transparent text-[16px] outline-none placeholder:text-muted-foreground"
            />
            <kbd className="rounded-md bg-muted px-1.5 py-0.5 font-sans text-[11px] text-muted-foreground ring-1 ring-border max-sm:hidden">esc</kbd>
          </div>

          <div id={listId} role="listbox" aria-label="Results" className="max-h-[min(64vh,520px)] overflow-y-auto overscroll-contain p-2">
            {nothing ? (
              <p className="px-3 pt-2 pb-1 text-sm text-muted-foreground">
                {loading && !index ? "Looking through your feeds…" : <>Nothing called “{q}” to go to.</>}
              </p>
            ) : null}
            {list.map((section) => (
              <div key={section.id} role="group" aria-labelledby={`${listId}-${section.id}`} className="pb-1">
                <div id={`${listId}-${section.id}`} className="px-3 pt-2.5 pb-1.5 text-[11px] font-bold tracking-[0.12em] text-muted-foreground uppercase">
                  {section.title}
                </div>
                {section.items.map((item) => {
                  const me = n++;
                  const on = me === current;
                  return (
                    <div
                      key={item.id}
                      id={optionId(me)}
                      role="option"
                      aria-selected={on}
                      onMouseMove={() => me !== current && setActive(me)}
                      onClick={() => choose(item)}
                      className={cn(
                        "flex min-h-11 cursor-pointer items-center gap-3 rounded-xl px-3 py-1.5 text-[15px] transition-colors duration-100",
                        on ? "bg-accent text-accent-foreground" : "text-foreground",
                      )}
                    >
                      <span
                        className={cn(
                          "grid size-8 shrink-0 place-items-center rounded-lg",
                          on ? "bg-card/70" : "bg-muted",
                          section.id === "ask" && "text-primary",
                        )}
                        aria-hidden="true"
                      >
                        <item.Icon className="size-4" />
                      </span>
                      <span className="min-w-0 flex-1 truncate font-medium">{item.label}</span>
                      {item.color ? <span className="size-2 shrink-0 rounded-full" style={{ background: item.color }} aria-hidden="true" /> : null}
                      {item.hint ? <span className="shrink-0 truncate text-[13px] text-muted-foreground max-sm:hidden">{item.hint}</span> : null}
                      {on ? <CornerDownLeftIcon className="size-4 shrink-0 text-muted-foreground" aria-hidden="true" /> : null}
                    </div>
                  );
                })}
              </div>
            ))}
            {!q && loading && !index ? <p className="px-3 pt-1 pb-2 text-sm text-muted-foreground">Gathering a few questions…</p> : null}
          </div>

          <div className="flex items-center gap-4 border-t bg-muted/50 px-4 py-2.5 text-xs text-muted-foreground max-sm:hidden">
            <span>
              <kbd className="font-sans">↑</kbd> <kbd className="font-sans">↓</kbd> to move
            </span>
            <span>
              <kbd className="font-sans">↵</kbd> to open
            </span>
            <span className="ml-auto">Anything else is a question for McFly</span>
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
}
