import type { ReactNode } from "react";

export function PageHeader({
  title,
  subtitle,
  eyebrow,
  actions,
}: {
  title: ReactNode;
  subtitle?: ReactNode;
  eyebrow?: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <header className="mb-6 flex flex-wrap items-end justify-between gap-x-6 gap-y-4">
      <div className="min-w-0">
        {eyebrow ? (
          <div className="mb-2 flex items-center gap-1.5 text-xs font-semibold tracking-wider text-muted-foreground uppercase">
            {eyebrow}
          </div>
        ) : null}
        <h1 className="font-heading text-[28px] leading-tight font-semibold tracking-tight max-md:text-2xl">{title}</h1>
        {subtitle ? <p className="mt-1.5 text-[15px] text-muted-foreground">{subtitle}</p> : null}
      </div>
      {actions ? <div className="flex flex-wrap gap-2.5">{actions}</div> : null}
    </header>
  );
}
