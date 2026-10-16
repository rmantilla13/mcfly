import { cn } from "cn";
import { cssColor } from "@/lib/format";
import styles from "./charts.module.css";

// A health dot: green and still when all is well, amber or red and slowly
// breathing when something needs a look, grey when nobody knows. Size it
// with className (size-2.5 by default). `pulse` overrides the breathing,
// e.g. an agent's own colour that breathes while it is pushing.

export type StatusState = "ok" | "warn" | "down" | "unknown";

const STATE_CLASS: Record<StatusState, string> = {
  ok: "text-success",
  warn: "text-warning",
  down: "text-destructive",
  unknown: "text-muted-foreground",
};

export function StatusDot({
  state = "unknown",
  color,
  pulse,
  label,
  className,
}: {
  state?: StatusState;
  // An agent's colour; wins over the state's when it is one (cssColor).
  color?: string | null;
  pulse?: boolean;
  label?: string;
  className?: string;
}) {
  const safe = cssColor(color);
  const breathe = pulse ?? (state === "warn" || state === "down");
  return (
    <span
      className={cn(styles.dot, "size-2.5", !safe && (STATE_CLASS[state] ?? STATE_CLASS.unknown), breathe && styles.breathe, className)}
      style={safe ? { color: safe } : undefined}
      role={label ? "img" : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
    />
  );
}
