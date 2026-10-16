import { cn } from "cn";
import type { CSSProperties, ReactNode } from "react";
import styles from "./charts.module.css";
import { type ChartTone, toneProps } from "./tone";

// A ring that fills clockwise from twelve o'clock: progress, uptime, how
// much of a window is left. `value` is 0..1. The arc sweeps in on first
// paint and eases to new values, in CSS, so it renders on the server.
// Anything passed as children sits in the middle.

const fine = (n: number) => Math.round(n * 100) / 100;

export function RingGauge({
  value,
  size = 72,
  stroke = 7,
  tone = "neutral",
  color,
  label,
  children,
  className,
}: {
  value: number;
  size?: number;
  stroke?: number;
  tone?: ChartTone;
  // An agent's colour; wins over `tone` when it is one (cssColor).
  color?: string | null;
  // What the ring shows ("Storage: 68%"), for screen readers.
  label?: string;
  children?: ReactNode;
  className?: string;
}) {
  const p = Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0;
  const centre = size / 2;
  const radius = Math.max(0, (size - stroke) / 2);
  const circumference = fine(2 * Math.PI * radius);
  const { className: toneClass, style } = toneProps(tone, color);

  return (
    <div
      className={cn("relative inline-grid shrink-0 place-items-center", toneClass, className)}
      style={{ ...style, width: size, height: size }}
      role={label ? "img" : undefined}
      aria-label={label}
    >
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="absolute inset-0" aria-hidden="true">
        <circle cx={centre} cy={centre} r={radius} fill="none" strokeWidth={stroke} className="stroke-foreground/10" />
        {/* Nothing at zero: a round cap on an empty arc still draws a dot. */}
        {p > 0 ? (
          <circle
            cx={centre}
            cy={centre}
            r={radius}
            fill="none"
            stroke="currentColor"
            strokeWidth={stroke}
            strokeLinecap="round"
            strokeDasharray={`${circumference} ${circumference}`}
            transform={`rotate(-90 ${centre} ${centre})`}
            className={styles.arc}
            style={{ strokeDashoffset: `${fine(circumference * (1 - p))}px`, "--ring-from": `${circumference}px` } as CSSProperties}
          />
        ) : null}
      </svg>
      {children ? <div className="relative flex flex-col items-center text-center leading-none text-foreground">{children}</div> : null}
    </div>
  );
}
