import { cn } from "cn";
import Link from "next/link";
import type { ReactNode } from "react";
import { AnimatedNumber } from "@/components/AnimatedNumber";
import { Card, CardContent, CardDescription, CardHeader } from "@/components/ui/card";
import type { NumberSpec } from "@/lib/widgets";

// Label · value · context line, as a Card. The value is a string as given,
// or `numeric` ({ value, format, … }, lib/widgets.ts), which counts up.
// Linked tiles lift on hover with a soft shadow under them.
export function StatTile({
  label,
  value,
  numeric,
  context,
  href,
  icon,
  tone,
}: {
  label: string;
  value?: string;
  numeric?: NumberSpec;
  context?: ReactNode;
  href?: string;
  icon?: ReactNode;
  tone?: "warn";
}) {
  const card = (
    <Card
      className={cn(
        "h-full gap-2",
        // Only translate and the shadow (the ring is a box-shadow too) move.
        // A shadow on the dark canvas has to be darker than the canvas, and
        // no token is: it is plain black there.
        href &&
          "transition-[translate,box-shadow] duration-300 ease-out group-hover/tile:shadow-lg group-hover/tile:shadow-foreground/10 group-hover/tile:ring-foreground/20 group-focus-visible/tile:ring-2 group-focus-visible/tile:ring-ring motion-safe:group-hover/tile:-translate-y-0.5 dark:group-hover/tile:shadow-black/50",
      )}
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
        {/* Not a CardTitle: in a small card its text-sm outranks any size given here. */}
        <div className="font-heading text-[30px] leading-none font-semibold tracking-tight">
          {numeric ? <AnimatedNumber {...numeric} /> : (value ?? "—")}
        </div>
        {context ? <div className="text-[13px] text-muted-foreground">{context}</div> : null}
      </CardContent>
    </Card>
  );
  return href ? (
    <Link href={href} className="group/tile block rounded-xl no-underline outline-none">
      {card}
    </Link>
  ) : (
    card
  );
}
