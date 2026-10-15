"use client";

import { cn } from "cn";
import { BotIcon, LayoutGridIcon, MonitorIcon, RssIcon, ScrollTextIcon, SlidersHorizontalIcon, SunIcon } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";

const LINKS = [
  { href: "/today", label: "Today", Icon: SunIcon },
  { href: "/", label: "Overview", Icon: LayoutGridIcon },
  { href: "/agents", label: "Agents", Icon: BotIcon },
  { href: "/feed", label: "Feed", Icon: RssIcon },
  { href: "/displays", label: "Displays", Icon: MonitorIcon },
  { href: "/settings", label: "Settings", Icon: SlidersHorizontalIcon },
  { href: "/audit", label: "Audit log", Icon: ScrollTextIcon },
];

export function NavLinks() {
  const pathname = usePathname();
  return (
    <nav className="flex flex-col gap-1 max-md:flex-row max-md:overflow-x-auto" aria-label="Console">
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
              "flex h-10 items-center gap-3 rounded-xl px-3.5 text-[15px] font-medium whitespace-nowrap text-sidebar-foreground/80 no-underline transition-colors hover:bg-sidebar-accent hover:text-sidebar-accent-foreground max-md:h-9 max-md:text-sm",
              active && "bg-sidebar-primary text-sidebar-primary-foreground shadow-md shadow-sidebar-primary/30 hover:bg-sidebar-primary hover:text-sidebar-primary-foreground",
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
