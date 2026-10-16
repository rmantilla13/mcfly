// The colour and the settings behind SkyBackdrop (components/SkyBackdrop.tsx),
// the console's port of the display's Backdrop
// (display/qml/components/Backdrop.qml): which backdrop the display chose,
// each sky's strength by day and at night and the resolution it runs at, the
// glow stops in OKLCh with the hues unwrapped as the shaders take them, and
// the glide from one palette to the next. Pure and without imports, so
// tests/sky.test.mjs can check it against Backdrop.qml's numbers.

import type { Mood } from "./mood";

// Displays → Customize → Backdrop (lib/types.ts DisplaySettings): the mesh
// (MeshGradient, with an aurora at night) or one of the five skies.
export type SkyStyle = "arc" | "ribbons" | "dawn" | "silk" | "pillars";
export type Backdrop = "mesh" | SkyStyle;
export const SKY_STYLES: readonly SkyStyle[] = ["arc", "ribbons", "dawn", "silk", "pillars"];

export type Rgb = [number, number, number];
export type Lab = [number, number, number]; // OKLab: lightness, a, b
export type Lch = [number, number, number]; // OKLCh: lightness, chroma, hue in radians

export const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

// Backdrop.qml's _looks: how much of the light lands on the canvas by day and
// at night (a pastel wash on the warm canvas, a glow on the near-black one),
// and the fraction of the size each runs at. The cost is simplex noise
// lookups per pixel, none (silk) to nine (ribbons), and a soft picture loses
// nothing scaled up.
export const SKY_LOOKS: Readonly<Record<SkyStyle, { strength: readonly [number, number]; resolution: number }>> = {
  arc: { strength: [0.7, 0.95], resolution: 0.5 },
  ribbons: { strength: [0.9, 1.0], resolution: 0.4 },
  dawn: { strength: [0.5, 0.9], resolution: 0.5 },
  silk: { strength: [0.5, 0.85], resolution: 0.5 },
  pillars: { strength: [0.85, 0.95], resolution: 0.5 },
};

// The strength part way into the night (`darkness` 0..1), times `brightness`.
export function skyStrength(style: SkyStyle, darkness: number, brightness = 1): number {
  const [day, night] = SKY_LOOKS[style].strength;
  return clamp((day + (night - day) * clamp(darkness, 0, 1)) * brightness, 0, 1);
}

// The display's fourth glow stop (Theme.qml: the last of each mood's glow
// array, its glowCream), which the console's --glow-1..3 tokens don't carry:
// a cream by day that the skies thin out into, a deep brown at night.
export const SKY_CREAM: Readonly<Record<Mood, string>> = {
  morning: "#fbe6b0",
  day: "#fbe6b0",
  evening: "#f6b94a",
  night: "#6b4a2a",
};

// Which backdrop the Ambient page draws: the display most recently seen (the
// one on the wall) chose it; `mesh` with no display or no key (what every
// display showed before there was a choice); and a name this build doesn't
// know is a sky, the arc, as the display's Backdrop draws it.
export type BackdropDevice = { last_seen_at: string | null; created_at: string; settings?: { backdrop?: string } | null };
export function displayBackdrop(devices: readonly BackdropDevice[]): Backdrop {
  const seen = (d: BackdropDevice) => Date.parse(d.last_seen_at ?? "") || 0;
  const latest = [...devices].sort((a, b) => seen(b) - seen(a) || Date.parse(b.created_at) - Date.parse(a.created_at))[0];
  const value = latest?.settings?.backdrop;
  if (!value || value === "mesh") return "mesh";
  return (SKY_STYLES as readonly string[]).includes(value) ? (value as SkyStyle) : "arc";
}

// ---- Colour

export function hexRgb(hex: string): Rgb {
  const h = hex.trim().replace(/^#/, "");
  const n = parseInt(h.length === 3 ? [...h].map((c) => c + c).join("") : h, 16);
  return [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255];
}

export function srgbToOklab([r, g, b]: Rgb): Lab {
  const lin = (c: number) => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
  const [R, G, B] = [lin(r), lin(g), lin(b)];
  const l = Math.cbrt(0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B);
  const m = Math.cbrt(0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B);
  const s = Math.cbrt(0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B);
  return [
    0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
  ];
}

export const labToLch = ([L, a, b]: Lab): Lch => [L, Math.hypot(a, b), Math.atan2(b, a)];
export const mixLab = (a: Lab, b: Lab, t: number): Lab => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];

// A grey has no hue of its own.
const GREY = 0.02;

// Backdrop.qml's _stops: each hue unwrapped toward the one before, so the
// shader's blend between neighbours takes the short way round; a grey stop
// takes its neighbour's hue (the aurora does the same).
export function unwrapHues(stops: readonly Lch[]): Lch[] {
  const known = stops.findIndex((s) => s[1] > GREY);
  let previous = known === -1 ? 0 : stops[known][2];
  return stops.map((s) => {
    let hue = s[1] > GREY ? s[2] : previous;
    while (hue - previous > Math.PI) hue -= 2 * Math.PI;
    while (hue - previous < -Math.PI) hue += 2 * Math.PI;
    previous = hue;
    return [s[0], s[1], hue];
  });
}

// The four stops the shaders take, from up to four colours; fewer, and the
// last is repeated, as Backdrop.qml pads (none at all: the day accent).
export function skyStops(colors: readonly Rgb[]): Lch[] {
  const src = colors.slice(0, 4);
  while (src.length < 4) src.push(src.length ? src[src.length - 1] : [0.31, 0.49, 0.97]);
  return unwrapHues(src.map((c) => labToLch(srgbToOklab(c))));
}

// One palette part way to another, stop by stop: lightness and chroma
// straight across, the hue the short way round (a grey stop takes its
// partner's hue), then unwrapped again for the shader.
export function blendStops(from: readonly Lch[], to: readonly Lch[], t: number): Lch[] {
  return unwrapHues(
    to.map((b, i) => {
      const a = from[i] ?? b;
      const ha = a[1] > GREY ? a[2] : b[2];
      const hb = b[1] > GREY ? b[2] : ha;
      const turn = hb - ha - 2 * Math.PI * Math.round((hb - ha) / (2 * Math.PI));
      return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, ha + turn * t];
    }),
  );
}

export const easeInOutSine = (t: number) => 0.5 - 0.5 * Math.cos(Math.PI * clamp(t, 0, 1));
