import { ZapIcon } from "lucide-react";
import Link from "next/link";
import { cn } from "cn";

// The lightning bolt on the glow, as in app/icon.svg.
export function BrandMark({ className }: { className?: string }) {
  return (
    <span
      className={cn(
        "inline-grid size-9 shrink-0 place-items-center rounded-xl bg-glow text-white shadow-md shadow-glow-2/30",
        className,
      )}
      aria-hidden="true"
    >
      <ZapIcon className="size-5" strokeWidth={2.25} fill="currentColor" />
    </span>
  );
}

export function Brand({ role = "Console" }: { role?: string }) {
  return (
    <Link href="/" className="flex items-center gap-3 rounded-lg px-2 py-1 text-foreground no-underline">
      <BrandMark />
      <span className="grid leading-tight">
        <span className="text-[17px] font-bold tracking-tight">McFly</span>
        <span className="text-xs font-semibold tracking-wider text-muted-foreground uppercase">{role}</span>
      </span>
    </Link>
  );
}
