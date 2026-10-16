"use client";

import { cn } from "cn";
import { useLayoutEffect, useRef, useSyncExternalStore } from "react";
import { countUpValue, formatFrame, formatValue, type NumberSpec } from "@/lib/widgets";

// A number that counts up: from 0 the first time it is on screen, and from
// what it showed before when the value changes. 700 ms, easing out like the
// display's AnimatedNumber.qml. The server renders the final text and so
// does the first client render, so hydration always matches; the counting
// happens afterwards, written straight into the span each frame rather than
// re-rendering. A number the server already painted on screen counts from
// 85% of itself, a short settle, rather than dropping to 0 in front of the
// reader. Without motion (prefers-reduced-motion) it just shows the value. The format is data (lib/widgets.ts NumberFormat), so a server
// component can pass it. Keep its key stable: a remount counts from 0 again.

const noSubscribe = () => () => {};

export function AnimatedNumber({
  value,
  format,
  decimals,
  currency,
  unit,
  prefix,
  suffix,
  duration = 700,
  className,
}: NumberSpec & { duration?: number; className?: string }) {
  const ref = useRef<HTMLSpanElement>(null);
  // The number on screen, or null until the first count has started.
  const shown = useRef<number | null>(null);
  const text = formatValue(value, { format, decimals, currency, unit, prefix, suffix });
  // True only on the hydrating render, when the server's text is already up.
  const hydrating = useSyncExternalStore(noSubscribe, () => false, () => true);
  const painted = useRef(hydrating);

  // A layout effect, so a client-side mount puts its first frame up before
  // the browser paints the final value.
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const spec = { format, decimals, currency, unit, prefix, suffix };
    const write = (v: number) => {
      el.textContent = formatFrame(v, value, spec);
    };
    if (!Number.isFinite(value) || window.matchMedia("(prefers-reduced-motion: reduce)").matches || typeof IntersectionObserver === "undefined") {
      shown.current = value;
      write(value);
      return;
    }

    let frame = 0;
    const count = (from: number) => {
      const start = performance.now();
      const tick = (now: number) => {
        const t = (now - start) / duration;
        shown.current = countUpValue(from, value, t, decimals);
        write(shown.current);
        if (t < 1) frame = requestAnimationFrame(tick);
      };
      shown.current = from;
      write(from);
      frame = requestAnimationFrame(tick);
    };

    let observer: IntersectionObserver | undefined;
    if (shown.current !== null) {
      if (shown.current !== value) count(shown.current);
      else write(value);
    } else {
      // On screen now: count straight away. Off screen: keep the real value
      // (for find-in-page and screen readers) until it scrolls into view.
      const box = el.getBoundingClientRect();
      const visible = box.width > 0 && box.bottom > 0 && box.right > 0 && box.top < window.innerHeight && box.left < window.innerWidth;
      if (visible) count(painted.current ? value * 0.85 : 0);
      else {
        observer = new IntersectionObserver((entries) => {
          if (!entries.some((entry) => entry.isIntersecting)) return;
          observer?.disconnect();
          count(0);
        });
        observer.observe(el);
      }
    }
    return () => {
      observer?.disconnect();
      cancelAnimationFrame(frame);
    };
  }, [value, format, decimals, currency, unit, prefix, suffix, duration]);

  return (
    <span ref={ref} className={cn("tabular-nums", className)} suppressHydrationWarning>
      {text}
    </span>
  );
}
