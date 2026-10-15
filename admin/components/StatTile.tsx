import { cn } from "cn";
import Link from "next/link";
import type { ReactNode } from "react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

// Label · value · context line, as a Card. Linked tiles lift on hover.
export function StatTile({
  label,
  value,
  context,
  href,
  icon,
  tone,
}: {
  label: string;
  value: string;
  context?: ReactNode;
  href?: string;
  icon?: ReactNode;
  tone?: "warn";
}) {
  const card = (
    <Card
      className={cn("h-full gap-2 transition-transform", href && "hover:-translate-y-px hover:ring-foreground/20")}
      size="sm"
    >
      <CardHeader className="flex items-center justify-between gap-2">
        <CardDescription className="text-sm font-medium">{label}</CardDescription>
        {icon ? (
          <span
            className={cn(
              "grid size-8 place-items-center rounded-lg bg-accent text-accent-foreground [&_svg]:size-[18px]",
              tone === "warn" && "bg-warning/12 text-warning",
            )}
            aria-hidden="true"
          >
            {icon}
          </span>
        ) : null}
      </CardHeader>
      <CardContent className="flex flex-col gap-1">
        <CardTitle className="font-heading text-[30px] leading-none font-semibold tracking-tight">{value}</CardTitle>
        {context ? <div className="text-[13px] text-muted-foreground">{context}</div> : null}
      </CardContent>
    </Card>
  );
  return href ? (
    <Link href={href} className="block no-underline">
      {card}
    </Link>
  ) : (
    card
  );
}
