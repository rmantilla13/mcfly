"use client";

import { cn } from "cn";
import { BookOpenIcon, BotIcon, CalendarIcon, SparklesIcon, LayoutGridIcon, MonitorIcon, RssIcon, ScrollTextIcon, SlidersHorizontalIcon, SunIcon } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useLayoutEffect, useRef } from "react";

const LINKS = [
  { href: "/today", label: "Today", Icon: SunIcon },
  { href: "/", label: "Overview", Icon: LayoutGridIcon },
  { href: "/agents", label: "Agents", Icon: BotIcon },
  { href: "/bots", label: "Grok bots", Icon: SparklesIcon },
  { href: "/memory", label: "Memory", Icon: BookOpenIcon },
  { href: "/calendars", label: "Calendars", Icon: CalendarIcon },
  { href: "/feed", label: "Feed", Icon: RssIcon },
  { href: "/displays", label: "Displays", Icon: MonitorIcon },
  { href: "/settings", label: "Settings", Icon: SlidersHorizontalIcon },
  { href: "/audit", label: "Audit log", Icon: ScrollTextIcon },
];

// The console's links. The active one sits on a pill that slides to the
// next link when you go there (down the sidebar, or along the row of links
// on a phone). The server draws the active link's own background; once the
// page is running the pill takes over at the same spot, so nothing moves on
// load, and it jumps (without sliding) whenever the links reflow.
export function NavLinks() {
  const pathname = usePathname();
  const navRef = useRef<HTMLElement>(null);
  const pillRef = useRef<HTMLSpanElement>(null);
  const placed = useRef(false);

  // A new page: slide there (the first time, just be there).
  useLayoutEffect(() => {
    const nav = navRef.current;
    const pill = pillRef.current;
    if (!nav || !pill) return;
    placePill(nav, pill, placed.current);
    // On a phone the links are a row that scrolls: bring the active one in.
    const link = nav.querySelector<HTMLElement>('[aria-current="page"]');
    if (link && nav.scrollWidth > nav.clientWidth) {
      const smooth = placed.current && !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      nav.scrollTo({ left: link.offsetLeft - (nav.clientWidth - link.offsetWidth) / 2, behavior: smooth ? "smooth" : "instant" });
    }
    placed.current = true;
    // From here the pill is the background (the links' in-data-[pill=on]).
    nav.dataset.pill = "on";
  }, [pathname]);

  // The links reflowed (the sidebar became a row, a font arrived): jump.
  // The observer's first report is only the sizes as they are, not a change.
  useEffect(() => {
    const nav = navRef.current;
    const pill = pillRef.current;
    if (!nav || !pill) return;
    let first = true;
    const resize = new ResizeObserver(() => {
      if (first) first = false;
      else placePill(nav, pill, false);
    });
    resize.observe(nav);
    for (const link of nav.querySelectorAll("a")) resize.observe(link);
    return () => resize.disconnect();
  }, []);

  return (
    <nav ref={navRef} className="relative flex flex-col gap-1 max-md:flex-row max-md:overflow-x-auto" aria-label="Console">
      <span
        ref={pillRef}
        aria-hidden="true"
        className="pointer-events-none absolute top-0 left-0 rounded-xl bg-sidebar-primary opacity-0 shadow-md shadow-sidebar-primary/30 motion-safe:transition-[transform,width,height] motion-safe:duration-300 motion-safe:ease-[cubic-bezier(0.2,0.8,0.2,1)]"
      />
      {LINKS.map(({ href, label, Icon }) => {
        // /pair belongs with the displays.
        const active =
          href === "/" ? pathname === "/" : pathname === href || pathname.startsWith(`${href}/`) || (href === "/displays" && pathname === "/pair");
        return (
          <Link
            key={href}
            href={href}
            aria-current={active ? "page" : undefined}
            className={cn(
              "relative flex h-10 items-center gap-3 rounded-xl px-3.5 text-[15px] font-medium whitespace-nowrap text-sidebar-foreground/80 no-underline transition-colors duration-300 hover:bg-sidebar-accent hover:text-sidebar-accent-foreground max-md:h-9 max-md:text-sm",
              active &&
                "bg-sidebar-primary text-sidebar-primary-foreground shadow-md shadow-sidebar-primary/30 hover:bg-sidebar-primary hover:text-sidebar-primary-foreground in-data-[pill=on]:bg-transparent in-data-[pill=on]:shadow-none in-data-[pill=on]:hover:bg-transparent",
            )}
          >
            <Icon className="size-[18px]" />
            {label}
          </Link>
        );
      })}
    </nav>
  );
}

// Puts the pill under the active link: sliding there, or jumping (no
// transition) for the first placement and for a reflow.
function placePill(nav: HTMLElement, pill: HTMLElement, slide: boolean) {
  const link = nav.querySelector<HTMLElement>('[aria-current="page"]');
  if (!link) {
    pill.style.opacity = "0";
    return;
  }
  if (!slide) pill.style.transition = "none";
  pill.style.width = `${link.offsetWidth}px`;
  pill.style.height = `${link.offsetHeight}px`;
  pill.style.transform = `translate(${link.offsetLeft}px, ${link.offsetTop}px)`;
  pill.style.opacity = "1";
  if (!slide) {
    void pill.offsetWidth; // commit the jump before the transition comes back
    pill.style.transition = "";
  }
}
