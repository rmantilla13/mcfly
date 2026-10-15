import { cn } from "cn";
import { ChevronLeftIcon, ChevronRightIcon, InboxIcon } from "lucide-react";
import Link from "next/link";
import type { ReactNode } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Empty, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty";
import { changeDirection, cssColor, formatChange, formatDateTime, formatRelative } from "@/lib/format";
import type { AgentKind, BriefKind, ProjectKind, ProjectStatus, ProjectUpdateKind } from "@/lib/types";

// Small server-renderable pieces shared by the tables.

// A relative time ("3 days ago") with the exact UTC time on hover. Inside a
// client component it renders on the server and again while hydrating, and
// the two can straddle a minute boundary; the server's text is kept then
// rather than failing hydration over "6 min. ago" vs "7 min. ago".
export function Time({ iso, fallback = "never" }: { iso: string | null | undefined; fallback?: string }) {
  if (!iso) return <span className="text-muted-foreground">{fallback}</span>;
  return (
    <time dateTime={iso} title={formatDateTime(iso)} className="whitespace-nowrap" suppressHydrationWarning>
      {formatRelative(iso)}
    </time>
  );
}

// An agent's color dot. Only hex colors are drawn; anything else gets the
// empty ring (cssColor).
export function Swatch({ color, className }: { color: string | null | undefined; className?: string }) {
  const safe = cssColor(color);
  return (
    <span
      className={cn("inline-block size-3 shrink-0 rounded-full ring-1 ring-foreground/10 ring-inset", className)}
      style={safe ? { background: safe } : undefined}
      aria-hidden="true"
    />
  );
}

// Swatch + name, the way an agent appears in every table.
export function AgentLabel({ name, color }: { name: string | null | undefined; color: string | null | undefined }) {
  if (!name) return <span className="text-muted-foreground">—</span>;
  return (
    <span className="inline-flex items-center gap-2">
      <Swatch color={color} />
      <span className="truncate">{name}</span>
    </span>
  );
}

const KIND_LABEL: Record<AgentKind, string> = { grok: "Grok", stocks: "Stocks", news: "News", other: "Other" };
const KIND_VARIANT: Record<AgentKind, "default" | "secondary" | "success" | "warning" | "outline"> = {
  grok: "default",
  stocks: "success",
  news: "warning",
  other: "outline",
};

export function KindBadge({ kind }: { kind: string }) {
  const k = (kind in KIND_LABEL ? kind : "other") as AgentKind;
  return <Badge variant={KIND_VARIANT[k]}>{KIND_LABEL[k]}</Badge>;
}

const BRIEF_KIND_VARIANT: Record<BriefKind, "secondary" | "destructive" | "outline"> = {
  hourly: "secondary",
  daily: "secondary",
  alert: "destructive",
  update: "outline",
};

export function BriefKindBadge({ kind }: { kind: string }) {
  const k = (kind in BRIEF_KIND_VARIANT ? kind : "update") as BriefKind;
  return <Badge variant={BRIEF_KIND_VARIANT[k]}>{k}</Badge>;
}

const PROJECT_STATUS_VARIANT: Record<ProjectStatus, "success" | "destructive" | "warning" | "secondary"> = {
  active: "success",
  blocked: "destructive",
  paused: "warning",
  done: "secondary",
};

export function ProjectStatusBadge({ status }: { status: ProjectStatus }) {
  return <Badge variant={PROJECT_STATUS_VARIANT[status] ?? "outline"}>{status}</Badge>;
}

export function ProjectKindBadge({ kind }: { kind: ProjectKind }) {
  return <Badge variant="outline">{kind}</Badge>;
}

const UPDATE_KIND_VARIANT: Record<ProjectUpdateKind, "outline" | "secondary" | "default" | "success" | "destructive"> = {
  note: "outline",
  commit: "secondary",
  pr: "default",
  ci: "secondary",
  deploy: "success",
  alert: "destructive",
  done: "success",
};

export function UpdateKindBadge({ kind }: { kind: ProjectUpdateKind }) {
  return <Badge variant={UPDATE_KIND_VARIANT[kind] ?? "outline"}>{kind}</Badge>;
}

// "+46 (+4.2%)" in green, red for a drop, muted when flat or absent.
export function Delta({ delta, pct, className }: { delta: number | null | undefined; pct: number | null | undefined; className?: string }) {
  const text = formatChange(delta, pct);
  if (text === "—") return <span className={cn("text-muted-foreground", className)}>—</span>;
  const direction = changeDirection(delta, pct);
  return (
    <span className={cn("tabular-nums", direction === "up" && "text-success", direction === "down" && "text-destructive", className)}>
      {text}
    </span>
  );
}

export function StatusBadge({ status }: { status: "ok" | "error" }) {
  return status === "ok" ? <Badge variant="success">ok</Badge> : <Badge variant="destructive">error</Badge>;
}

export function EmptyState({ title, children, icon }: { title: string; children?: ReactNode; icon?: ReactNode }) {
  return (
    <Empty className="py-12">
      <EmptyHeader>
        <EmptyMedia variant="icon">{icon ?? <InboxIcon />}</EmptyMedia>
        <EmptyTitle>{title}</EmptyTitle>
        {children ? <EmptyDescription>{children}</EmptyDescription> : null}
      </EmptyHeader>
    </Empty>
  );
}

export function Pagination({
  page,
  hasMore,
  href,
  shown,
}: {
  page: number;
  hasMore: boolean;
  href: (page: number) => string;
  shown: number;
}) {
  if (page <= 1 && !hasMore) return null;
  return (
    <nav className="flex items-center justify-between gap-3 border-t px-4 py-3 text-[13px] text-muted-foreground" aria-label="Pagination">
      <span>
        Page {page} · {shown} shown
      </span>
      <div className="flex gap-2">
        {page > 1 ? (
          <Button variant="outline" size="sm" asChild>
            <Link href={href(page - 1)}>
              <ChevronLeftIcon data-icon="inline-start" />
              Previous
            </Link>
          </Button>
        ) : null}
        {hasMore ? (
          <Button variant="outline" size="sm" asChild>
            <Link href={href(page + 1)}>
              Next
              <ChevronRightIcon data-icon="inline-end" />
            </Link>
          </Button>
        ) : null}
      </div>
    </nav>
  );
}

// Builds "?tab=..&page=.." links that keep the other parameters.
export function pageHref(path: string, params: Record<string, string | undefined>) {
  return (page: number) => {
    const sp = new URLSearchParams();
    for (const [k, v] of Object.entries(params)) if (v) sp.set(k, v);
    if (page > 1) sp.set("page", String(page));
    const qs = sp.toString();
    return qs ? `${path}?${qs}` : path;
  };
}

export function readPage(value: string | string[] | undefined): number {
  const n = Number(Array.isArray(value) ? value[0] : value);
  return Number.isInteger(n) && n > 0 && n < 100_000 ? n : 1;
}

export function readString(value: string | string[] | undefined): string {
  return (Array.isArray(value) ? value[0] : value)?.trim().slice(0, 200) ?? "";
}

// Table cells that line up numbers.
export const numCell = "text-right tabular-nums";
