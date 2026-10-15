import { ScrollTextIcon } from "lucide-react";
import Link from "next/link";
import { EmptyState, Time, numCell } from "@/components/bits";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { describeAction } from "@/lib/format";
import type { AuditEntry } from "@/lib/types";

type Variant = "default" | "secondary" | "destructive" | "outline" | "success" | "warning";

const VARIANTS: Record<string, Variant> = {
  create_agent: "default",
  rotate_agent_key: "default",
  update_agent: "secondary",
  revoke_agent: "warning",
  delete_agent: "destructive",
  delete_brief: "destructive",
  set_symbol: "secondary",
  delete_symbol: "destructive",
  delete_news_report: "destructive",
  rename_device: "secondary",
  revoke_device: "destructive",
  pair_device: "success",
  update_settings: "secondary",
  set_admin: "default",
  delete_project: "destructive",
  set_metric: "secondary",
  delete_metric: "destructive",
  set_dashboard: "secondary",
  delete_dashboard: "destructive",
  delete_event: "destructive",
  delete_calendar: "destructive",
};

function variant(e: AuditEntry): Variant {
  if (e.action === "set_admin") return e.details.make_admin ? "default" : "warning";
  return VARIANTS[e.action] ?? "outline";
}

const str = (v: unknown) => (typeof v === "string" && v ? v : null);

// What the entry was about, linked where the console has a page for it.
function Target({ e }: { e: AuditEntry }) {
  const d = e.details;
  switch (e.target_type) {
    case "agent": {
      const label = str(d.name) ?? `Agent ${e.target_id?.slice(0, 8) ?? ""}`.trim();
      return e.action === "delete_agent" ? <span>{label}</span> : <Link href="/agents">{label}</Link>;
    }
    case "brief":
      return <span>{str(d.title) ?? "Brief"}</span>;
    case "symbol":
      return (
        <Link href="/feed?tab=markets" className="font-mono">
          {e.target_id ?? "Symbol"}
        </Link>
      );
    case "news_report":
      return e.action === "delete_news_report" || !e.target_id ? (
        <span className="font-mono">{str(d.slug) ?? "Report"}</span>
      ) : (
        <Link href={`/feed/news/${e.target_id}`} className="font-mono">
          {str(d.slug) ?? "Report"}
        </Link>
      );
    case "device": {
      const label = str(d.name) ?? `Display ${e.target_id?.slice(0, 8) ?? ""}`.trim();
      return e.action === "revoke_device" ? <span>{label}</span> : <Link href="/displays">{label}</Link>;
    }
    case "project": {
      const label = str(d.name) ?? `Project ${e.target_id?.slice(0, 8) ?? ""}`.trim();
      return e.action === "delete_project" || !e.target_id ? <span>{label}</span> : <Link href={`/feed/projects/${e.target_id}`}>{label}</Link>;
    }
    case "metric":
      return (
        <Link href="/feed?tab=metrics" className="font-mono">
          {e.target_id ?? "Metric"}
        </Link>
      );
    case "dashboard": {
      const label = str(d.key) ?? `Dashboard ${e.target_id?.slice(0, 8) ?? ""}`.trim();
      return e.action === "delete_dashboard" || !e.target_id ? (
        <span className="font-mono">{label}</span>
      ) : (
        <Link href={`/feed/dashboards/${e.target_id}`} className="font-mono">
          {label}
        </Link>
      );
    }
    case "event":
      return <span>{str(d.title) ?? "Event"}</span>;
    case "calendar":
      return <Link href="/feed?tab=calendar">{e.target_id ?? "Calendar"} calendar</Link>;
    case "settings":
      return <Link href="/settings">Platform settings</Link>;
    case "user":
      return <span>{str(d.email) ?? e.target_id ?? "User"}</span>;
    default:
      return <span className="text-muted-foreground">{e.target_id ?? "—"}</span>;
  }
}

const SKIP = new Set(["name", "title", "slug", "key", "email", "make_admin", "demo"]);

function detailText(e: AuditEntry): string {
  return Object.entries(e.details)
    .filter(([k, v]) => !SKIP.has(k) && v !== null && v !== undefined && v !== "")
    .map(([k, v]) => {
      const key = k.replaceAll("_", " ");
      if (typeof v === "boolean") return `${key}: ${v ? "yes" : "no"}`;
      if (typeof v === "object") return `${key}: ${JSON.stringify(v)}`;
      return `${key}: ${String(v)}`;
    })
    .join(" · ");
}

export function AuditTable({ entries }: { entries: AuditEntry[] }) {
  if (entries.length === 0) {
    return (
      <EmptyState title="Nothing yet" icon={<ScrollTextIcon />}>
        Admin actions show up here as they happen.
      </EmptyState>
    );
  }
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead className="pl-4">Action</TableHead>
          <TableHead>Target</TableHead>
          <TableHead>Details</TableHead>
          <TableHead>Admin</TableHead>
          <TableHead className={`${numCell} pr-4`}>When</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {entries.map((e) => {
          const details = detailText(e);
          return (
            <TableRow key={e.id}>
              <TableCell className="pl-4">
                <Badge variant={variant(e)}>{describeAction(e.action, e.details)}</Badge>
              </TableCell>
              <TableCell className="font-medium">
                <Target e={e} />
              </TableCell>
              <TableCell className="max-w-md whitespace-normal text-muted-foreground">{details || "—"}</TableCell>
              <TableCell>{e.admin_email ?? <span className="text-muted-foreground">system</span>}</TableCell>
              <TableCell className={`${numCell} pr-4`}>
                <Time iso={e.created_at} />
              </TableCell>
            </TableRow>
          );
        })}
      </TableBody>
    </Table>
  );
}
