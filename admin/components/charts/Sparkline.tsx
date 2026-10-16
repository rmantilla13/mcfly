import { cn } from "cn";
import { useId } from "react";
import { areaPath, lastPoint, smoothPath } from "@/lib/widgets";
import styles from "./charts.module.css";
import { type ChartTone, toneProps } from "./tone";

// A small trend line: a smooth line, a soft fill under it (28% → 0, like the
// display's Sparkline.qml) and a dot on the newest point. It stretches to
// fill its box, so size it with className (h-10 w-full by default). No
// client JavaScript: it renders on the server and wipes in with CSS.

const W = 120;
const H = 32;
const PAD = 2;

export function Sparkline({
  points,
  tone = "neutral",
  color,
  label,
  dot = true,
  fill = true,
  strokeWidth = 1.75,
  className,
}: {
  points: number[];
  tone?: ChartTone;
  // An agent's colour; wins over `tone` when it is one (cssColor).
  color?: string | null;
  // What the line shows, for screen readers. Without one it is decoration.
  label?: string;
  dot?: boolean;
  fill?: boolean;
  strokeWidth?: number;
  className?: string;
}) {
  // A gradient is found by id, and two sparklines on a page must not share one.
  const fillId = `spark-${useId().replace(/[^\w-]/g, "")}`;
  const values = points.filter(Number.isFinite);
  if (values.length === 0) return null;
  const line = smoothPath(values, W, H, PAD);
  const area = fill ? areaPath(values, W, H, PAD) : "";
  const end = dot && values.length > 1 ? lastPoint(values, W, H, PAD) : null;
  const { className: toneClass, style } = toneProps(tone, color);

  return (
    <div
      className={cn("relative h-10 w-full", toneClass, className)}
      style={style}
      role={label ? "img" : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
    >
      <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" className={cn("absolute inset-0 size-full", styles.reveal)} aria-hidden="true">
        {area ? (
          <>
            <defs>
              <linearGradient id={fillId} gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" y2={H}>
                <stop offset="0" stopColor="currentColor" stopOpacity={0.28} />
                <stop offset="1" stopColor="currentColor" stopOpacity={0} />
              </linearGradient>
            </defs>
            <path d={area} fill={`url(#${fillId})`} />
          </>
        ) : null}
        <path
          d={line}
          fill="none"
          stroke="currentColor"
          strokeWidth={strokeWidth}
          strokeLinecap="round"
          strokeLinejoin="round"
          vectorEffect="non-scaling-stroke"
        />
      </svg>
      {/* An HTML dot, because a circle in a stretched SVG would be an oval. */}
      {end ? (
        <span
          className={cn("absolute size-1.5 rounded-full bg-current", styles.pop)}
          style={{ left: `${(end.x / W) * 100}%`, top: `${(end.y / H) * 100}%` }}
        />
      ) : null}
    </div>
  );
}
