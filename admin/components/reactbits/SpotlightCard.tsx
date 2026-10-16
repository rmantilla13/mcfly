/*
 * SpotlightCard, from React Bits (https://github.com/DavidHDev/react-bits,
 * src/ts-tailwind/Components/SpotlightCard, commit d9085a5), ported for
 * McFly.
 *
 * MIT + Commons Clause License Condition v1.0
 *
 * Copyright (c) 2026 David Haz
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, and distribute the Software as part of
 * an application, website, or product, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * Commons Clause Restriction: You may use this Software, including for any
 * commercial purpose, so long as you do not sell, sublicense, or redistribute the
 * components themselves-whether alone, in a bundle, or as a ported version.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 * Changes for McFly: the light and the engine that moves it are split from
 * the card, as `Spotlight` — the four layers alone, lit against whatever
 * element holds them (the Today page's tiles are already cards, some of
 * them links). Its strength is not a theme prop but two custom properties,
 * --spotlight-fill and --spotlight-rim, so one element can be lit for the
 * light scheme and the dark one through `dark:` classes; its colour defaults
 * to the page's --foreground, which is light on dark and dark on light as
 * the original's palettes were. SpotlightCard itself is the original card,
 * drawn with Spotlight inside it. A light out of reach of the pointer stays
 * asleep (a move far away wakes nothing), and one that has gone dark stops
 * at once rather than gliding unseen after the pointer.
 */
"use client";

import { useEffect, useRef, type CSSProperties, type HTMLAttributes, type RefObject } from "react";

export type SpotlightShape = "circle" | "beam";

export type SpotlightProps = {
  spotlightColor?: string;
  intensity?: number;
  spotlightSize?: number;
  softness?: number;
  shape?: SpotlightShape;
  borderGlow?: number;
  proximity?: number;
  smoothing?: number;
  ambient?: boolean;
  flare?: boolean;
  grain?: number;
  // The static hairline the original draws round the card; off where the
  // element has a border of its own.
  border?: boolean;
  className?: string;
};

export type SpotlightCardProps = HTMLAttributes<HTMLDivElement> & SpotlightProps & { theme?: "dark" | "light" };

type Palette = { surface: string; border: string; shadow: string; light: string; fill: number; edge: number };

type Settings = {
  shape: SpotlightShape;
  fill: string;
  edge: string;
  size: number;
  intensity: number;
  borderGlow: number;
  proximity: number;
  smoothing: number;
  ambient: boolean;
  flare: boolean;
  grain: number;
};

const THEMES: Record<"dark" | "light", Palette> = {
  dark: {
    surface: "#111111",
    border: "rgba(255, 255, 255, 0.08)",
    shadow: "0 24px 48px -24px rgba(0, 0, 0, 0.6)",
    light: "#ffffff",
    fill: 1,
    edge: 1,
  },
  light: {
    surface: "#ffffff",
    border: "rgba(24, 24, 27, 0.1)",
    shadow: "0 1px 2px rgba(24, 24, 27, 0.04), 0 18px 40px -20px rgba(24, 24, 27, 0.16)",
    light: "#18181b",
    fill: 0.28,
    edge: 0.7,
  },
};

const SHAPES: SpotlightShape[] = ["circle", "beam"];

const NOISE =
  "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='2' stitchTiles='stitch'/%3E%3CfeColorMatrix type='saturate' values='0'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E\")";

const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));

const falloff = (color: string, softness: number) => {
  const soft = clamp(softness, 0, 1);
  const core = (1 - soft) ** 1.5 * 0.85;
  const stop = (alpha: number, at: number) => `color-mix(in srgb, ${color} ${(alpha * 100).toFixed(2)}%, transparent) ${(at * 100).toFixed(2)}%`;
  const list = [stop(1, 0)];
  for (let i = 0; i <= 14; i++) {
    const t = core + ((1 - core) * i) / 14;
    const g = (t - core) / (1 - core);
    const smooth = 1 - g * g * (3 - 2 * g);
    const glow = Math.exp(-4.6 * g * g) * (1 - g ** 6);
    list.push(stop(smooth + (glow - smooth) * soft, t));
  }
  return list.join(", ");
};

const MASK_RING =
  "[-webkit-mask:linear-gradient(#000_0_0)_content-box,linear-gradient(#000_0_0)] [-webkit-mask-composite:xor] [mask:linear-gradient(#000_0_0)_content-box_exclude,linear-gradient(#000_0_0)]";

// The light itself: the layers, and the engine that follows the pointer (or
// the focus) across `root` — the element the first layer sits in.
function useSpotlight(
  lightRef: RefObject<HTMLSpanElement | null>,
  grainRef: RefObject<HTMLSpanElement | null>,
  edgeRef: RefObject<HTMLSpanElement | null>,
  settingsRef: RefObject<Settings>,
) {
  const wakeRef = useRef<(() => void) | null>(null);

  useEffect(() => {
    wakeRef.current?.();
  });

  useEffect(() => {
    const light = lightRef.current;
    const noise = grainRef.current;
    const edge = edgeRef.current;
    const root = light?.parentElement;
    if (!root || !light || !noise || !edge) return undefined;

    const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
    const state = { x: 0, y: 0, presence: 0, flare: 0, time: Math.random() * 60, pressed: false, visible: true };
    const pointer = { x: 0, y: 0, active: false };
    const drawn = { light: "", edge: "", noise: "" };
    let focus: Element | null = null;
    let raf = 0;
    let last = 0;
    let alive = true;
    let dark = false;

    const gradient = (s: Settings, size: number, x: number, y: number, stops: string) => {
      if (s.shape === "beam") {
        const reach = Math.max(size * 0.6, y + size * 0.55);
        return `radial-gradient(${(size * 0.55).toFixed(1)}px ${reach.toFixed(1)}px at ${x.toFixed(1)}px 0px, ${stops})`;
      }
      return `radial-gradient(circle ${size.toFixed(1)}px at ${x.toFixed(1)}px ${y.toFixed(1)}px, ${stops})`;
    };

    const paint = (s: Settings) => {
      const size = s.size * (1 + 0.2 * state.flare);
      const boost = 1 + 0.7 * state.flare;
      const fill = gradient(s, size, state.x, state.y, s.fill);
      const rim = gradient(s, size * 0.6, state.x, s.shape === "beam" ? 0 : state.y, s.edge);
      if (fill !== drawn.light) {
        drawn.light = fill;
        light.style.background = fill;
      }
      if (rim !== drawn.edge) {
        drawn.edge = rim;
        edge.style.background = rim;
      }
      // How present the light is; the layers scale it by --spotlight-fill
      // and --spotlight-rim, which the scheme sets.
      light.style.setProperty("--spotlight-presence", String(Math.min(1, state.presence * s.intensity * boost)));
      edge.style.setProperty("--spotlight-presence", String(Math.min(1, state.presence * s.borderGlow * boost)));
      const grainy = s.grain > 0 ? gradient(s, size, state.x, state.y, "#000 0%, transparent 100%") : "none";
      if (grainy !== drawn.noise) {
        drawn.noise = grainy;
        noise.style.webkitMaskImage = grainy;
        noise.style.maskImage = grainy;
      }
      noise.style.opacity = String(state.presence * s.grain);
    };

    const tick = (now: number) => {
      raf = 0;
      if (!alive) return;
      const s = settingsRef.current;
      const dt = Math.min(0.05, Math.max(0.001, (now - last) / 1000));
      last = now;
      const rect = root.getBoundingClientRect();
      let tx = state.x;
      let ty = state.y;
      let target = 0;
      if (focus && root.contains(focus)) {
        const box = focus.getBoundingClientRect();
        tx = box.left + box.width / 2 - rect.left;
        ty = box.top + box.height / 2 - rect.top;
        target = 1;
      } else if (pointer.active) {
        tx = pointer.x - rect.left;
        ty = pointer.y - rect.top;
        const gap = Math.hypot(Math.max(0, -tx, tx - rect.width), Math.max(0, -ty, ty - rect.height));
        if (gap === 0) target = 1;
        else if (s.proximity > 0) target = Math.max(0, 1 - gap / s.proximity) ** 2;
      }
      if (target < 0.6 && s.ambient && state.visible) {
        if (!reduce) state.time += dt;
        const drift = 0.6 - target;
        tx += (rect.width * (0.5 + 0.34 * Math.sin(state.time * 0.43)) - tx) * (drift / 0.6);
        ty += (rect.height * (0.5 + 0.3 * Math.sin(state.time * 0.61 + 1.3)) - ty) * (drift / 0.6);
        target = 0.6;
      }
      if (state.presence < 0.02 && target > 0 && !s.ambient) {
        state.x = tx;
        state.y = ty;
      }
      const follow = reduce || s.smoothing === 0 ? 1 : 1 - Math.exp(-dt / (0.015 + s.smoothing * 0.22));
      state.x += (tx - state.x) * follow;
      state.y += (ty - state.y) * follow;
      const fade = reduce ? 1 : 1 - Math.exp(-dt / (target > state.presence ? 0.1 : 0.32));
      state.presence += (target - state.presence) * fade;
      if (Math.abs(target - state.presence) < 0.002) state.presence = target;
      const press = state.pressed && s.flare && !reduce ? 1 : 0;
      state.flare += (press - state.flare) * (1 - Math.exp(-dt / (press ? 0.05 : 0.28)));
      if (Math.abs(press - state.flare) < 0.002) state.flare = press;
      // Dark and staying dark: nothing to draw or follow. Stand where the
      // light would be and stop, after one paint that puts it out.
      if (target === 0 && state.presence === 0 && state.flare === 0) {
        state.x = tx;
        state.y = ty;
        if (!dark) paint(s);
        dark = true;
        return;
      }
      dark = false;
      paint(s);
      const moving = Math.abs(tx - state.x) > 0.1 || Math.abs(ty - state.y) > 0.1;
      const settled = !moving && state.presence === target && state.flare === press;
      if (!settled || (s.ambient && state.visible && !reduce)) raf = requestAnimationFrame(tick);
    };

    const wake = () => {
      if (raf || !alive) return;
      last = performance.now();
      raf = requestAnimationFrame(tick);
    };
    wakeRef.current = wake;

    // Whether a pointer at (x, y) could light it: on it, or within
    // `proximity`. Read in the event, while layout is still clean, so a move
    // across the page doesn't wake every light into a frame of its own.
    const inReach = (x: number, y: number) => {
      const s = settingsRef.current;
      if (s.ambient) return true;
      if (s.proximity <= 0) return false;
      const r = root.getBoundingClientRect();
      return Math.hypot(Math.max(0, r.left - x, x - r.right), Math.max(0, r.top - y, y - r.bottom)) < s.proximity;
    };

    const onMove = (event: PointerEvent) => {
      pointer.x = event.clientX;
      pointer.y = event.clientY;
      pointer.active = true;
      if (state.presence > 0 || root.contains(event.target as Node | null) || inReach(pointer.x, pointer.y)) wake();
    };
    const onOut = (event: PointerEvent) => {
      if (event.relatedTarget) return;
      pointer.active = false;
      wake();
    };
    const onDown = (event: PointerEvent) => {
      pointer.x = event.clientX;
      pointer.y = event.clientY;
      pointer.active = true;
      state.pressed = true;
      wake();
    };
    const onUp = (event: PointerEvent) => {
      if (event.pointerType !== "mouse") pointer.active = false;
      if (!state.pressed && event.pointerType === "mouse") return;
      state.pressed = false;
      wake();
    };
    const onFocusIn = (event: FocusEvent) => {
      if (!(event.target instanceof Element) || !event.target.matches(":focus-visible")) return;
      focus = event.target;
      wake();
    };
    const onFocusOut = (event: FocusEvent) => {
      if (root.contains(event.relatedTarget as Node | null)) return;
      focus = null;
      wake();
    };
    const onScroll = () => {
      if (state.presence > 0 || (pointer.active && inReach(pointer.x, pointer.y))) wake();
    };

    const observer = new IntersectionObserver((entries) => {
      state.visible = entries.some((entry) => entry.isIntersecting);
      if (state.visible) wake();
    });
    observer.observe(root);
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
    window.addEventListener("pointercancel", onUp);
    window.addEventListener("scroll", onScroll, { capture: true, passive: true });
    document.addEventListener("pointerout", onOut);
    root.addEventListener("pointerdown", onDown);
    root.addEventListener("focusin", onFocusIn);
    root.addEventListener("focusout", onFocusOut);
    wake();

    return () => {
      alive = false;
      cancelAnimationFrame(raf);
      observer.disconnect();
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      window.removeEventListener("pointercancel", onUp);
      window.removeEventListener("scroll", onScroll, { capture: true });
      document.removeEventListener("pointerout", onOut);
      root.removeEventListener("pointerdown", onDown);
      root.removeEventListener("focusin", onFocusIn);
      root.removeEventListener("focusout", onFocusOut);
      wakeRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
}

function settingsOf(p: SpotlightProps, color: string, fill: number, edge: number): Settings {
  return {
    shape: SHAPES.includes(p.shape ?? "circle") ? (p.shape ?? "circle") : "circle",
    fill: falloff(color, p.softness ?? 0.7),
    edge: falloff(color, 1),
    size: Math.max(20, p.spotlightSize ?? 240),
    intensity: clamp(p.intensity ?? 0.15, 0, 1) * fill,
    borderGlow: clamp(p.borderGlow ?? 0.6, 0, 1) * edge,
    proximity: Math.max(0, p.proximity ?? 80),
    smoothing: clamp(p.smoothing ?? 0.3, 0, 1),
    ambient: p.ambient ?? false,
    flare: p.flare ?? true,
    grain: clamp(p.grain ?? 0, 0, 1),
  };
}

/**
 * The light alone, for an element that is already a card: put it first
 * among the element's children, and give the element `relative isolate`
 * and its rounded corners (the layers take `rounded-[inherit]`). The
 * element sets --spotlight-fill and --spotlight-rim — the original's
 * light-scheme strengths are 0.28 and 0.7, its dark ones 1 and 1 — or
 * takes the defaults here, which are the dark ones.
 */
export function Spotlight({ spotlightColor = "var(--foreground)", border = false, className = "", ...props }: SpotlightProps) {
  const lightRef = useRef<HTMLSpanElement>(null);
  const grainRef = useRef<HTMLSpanElement>(null);
  const edgeRef = useRef<HTMLSpanElement>(null);
  const settingsRef = useRef<Settings>(settingsOf(props, spotlightColor, 1, 1));
  useEffect(() => {
    settingsRef.current = settingsOf(props, spotlightColor, 1, 1);
  });
  useSpotlight(lightRef, grainRef, edgeRef, settingsRef);
  // The light's opacity class ends with a space before the caller's classes:
  // Tailwind's scanner misses a candidate that runs straight into `${`.
  return (
    <>
      <span
        ref={lightRef}
        className={`pointer-events-none absolute inset-0 -z-10 rounded-[inherit] opacity-[calc(var(--spotlight-presence,0)*var(--spotlight-fill,1))] ${className}`}
        aria-hidden="true"
      />
      <span
        ref={grainRef}
        className="pointer-events-none absolute inset-0 -z-10 rounded-[inherit] bg-[length:160px_160px] opacity-0 mix-blend-overlay"
        style={{ backgroundImage: NOISE }}
        aria-hidden="true"
      />
      {border ? (
        <span className={`pointer-events-none absolute inset-0 z-[1] rounded-[inherit] p-px [background:var(--spotlight-card-border)] ${MASK_RING}`} aria-hidden="true" />
      ) : null}
      <span
        ref={edgeRef}
        className={`pointer-events-none absolute inset-0 z-[1] rounded-[inherit] p-px opacity-[calc(var(--spotlight-presence,0)*var(--spotlight-rim,1))] ${MASK_RING}`}
        aria-hidden="true"
      />
    </>
  );
}

export default function SpotlightCard({ children, className = "", style, theme = "dark", spotlightColor, ...rest }: SpotlightCardProps) {
  const {
    intensity,
    spotlightSize,
    softness,
    shape,
    borderGlow,
    proximity,
    smoothing,
    ambient,
    flare,
    grain,
    border = true,
    ...div
  } = rest;
  const palette = THEMES[theme] ?? THEMES.dark;
  return (
    <div
      className={`relative isolate overflow-hidden rounded-3xl p-8 [background-color:var(--spotlight-card-surface)] [box-shadow:var(--spotlight-card-shadow)]${className ? ` ${className}` : ""}`}
      style={
        {
          "--spotlight-card-surface": palette.surface,
          "--spotlight-card-border": palette.border,
          "--spotlight-card-shadow": palette.shadow,
          "--spotlight-fill": palette.fill,
          "--spotlight-rim": palette.edge,
          ...style,
        } as CSSProperties
      }
      {...div}
    >
      <Spotlight
        spotlightColor={spotlightColor ?? palette.light}
        intensity={intensity}
        spotlightSize={spotlightSize}
        softness={softness}
        shape={shape}
        borderGlow={borderGlow}
        proximity={proximity}
        smoothing={smoothing}
        ambient={ambient}
        flare={flare}
        grain={grain}
        border={border}
      />
      {children}
    </div>
  );
}
