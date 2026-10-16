// The colour and motion behind MeshGradient (components/MeshGradient.tsx),
// the console's port of the display's GradientTile: the palette it derives
// from the glow tokens or one colour, and where its colour fields and glass
// rings drift to at a given moment. Pure and without imports, so
// tests/mesh.test.mjs can check it against GradientTile.qml's numbers.

// ---- Colour

export type Rgb = [number, number, number];
type Hsl = { h: number; s: number; l?: number; nh?: number };

export const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
export const wrap = (h: number) => h - Math.floor(h);

export function srgbToOklab([r, g, b]: Rgb): Rgb {
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

function toHsl([r, g, b]: Rgb): Hsl {
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  const d = max - min;
  if (d < 1e-6) return { h: 0, s: 0, l }; // grey: no hue, as Qt says
  const s = d / (1 - Math.abs(2 * l - 1));
  const h = max === r ? ((g - b) / d + 6) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return { h: h / 6, s, l };
}

function fromHsl(h: number, s: number, l: number): Rgb {
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const x = c * (1 - Math.abs(((h * 6) % 2) - 1));
  const m = l - c / 2;
  const k = Math.floor(wrap(h) * 6);
  const [r, g, b] = [
    [c, x, 0],
    [x, c, 0],
    [0, c, x],
    [0, x, c],
    [x, 0, c],
    [c, 0, x],
  ][k];
  return [r + m, g + m, b + m];
}

// Pastel saturation: lively but never neon; greys stay grey.
const pastel = (s: number) => (s < 0.08 ? s : clamp(s, 0.38, 0.78));

// GradientTile.qml's palette: [main, analogous +, analogous -, highlight],
// as OKLab, for the day (pastel) or the night (deep). From 3-4 colours, or
// from one (two analogous hues and a highlight, narrower at night so warm
// tiles don't go olive).
export function meshPalette(source: Rgb[], dark: boolean): Rgb[] {
  let src: Hsl[];
  if (source.length >= 3) {
    src = source.slice(0, 4).map(toHsl);
    if (src.length < 4) src.push({ h: wrap(src[0].h + 0.03), s: src[0].s * 0.7 });
  } else {
    const b = toHsl(source[0] ?? [0.36, 0.49, 0.96]);
    src = [
      { h: b.h, s: b.s },
      { h: wrap(b.h + 0.075), s: b.s * 0.95, nh: wrap(b.h + 0.03) },
      { h: wrap(b.h - 0.085), s: b.s * 0.9, nh: wrap(b.h - 0.035) },
      { h: wrap(b.h + 0.03), s: b.s * 0.7, nh: b.h },
    ];
  }
  const day: [number, number, number][] = [
    [src[0].h, pastel(src[0].s), 0.79],
    [src[1].h, pastel(src[1].s), 0.83],
    [src[2].h, pastel(src[2].s), 0.76],
    [src[3].h, pastel(src[3].s) * 0.8, 0.94],
  ];
  const nh = (i: number) => src[i].nh ?? src[i].h;
  const night: [number, number, number][] = [
    [nh(0), pastel(src[0].s) * 0.55, 0.19],
    [nh(1), pastel(src[1].s) * 0.5, 0.22],
    [nh(2), pastel(src[2].s) * 0.5, 0.15],
    [nh(3), pastel(src[3].s) * 0.45, 0.27],
  ];
  return (dark ? night : day).map(([h, s, l]) => srgbToOklab(fromHsl(h, s, l)));
}

// ---- Motion (pure)

// Three sines at 1, φ and e times the rate: no two ever line up again.
const wander = (w: number, a: number, b: number, c: number) =>
  0.62 * Math.sin(w + a) + 0.28 * Math.sin(1.618034 * w + b) + 0.1 * Math.sin(2.718282 * w + c);

// Each coordinate's own rate (the display's 1x and 2x, pulled apart).
const RATES = [1.0, 0.87, 1.93, 1.11, 0.79, 2.07, 1.17, 1.89, 0.93, 1.71, 1.03, 0.83];

// Coordinate i's offset from home at time t, up to about `amp` either way.
const axis = (t: number, s: number, i: number, amp: number) =>
  amp * wander(t * RATES[i] + s * (1.3 + 0.37 * i), 0.7 * i + s, 1.9 * i + 0.4, 2.3 * i + s * 0.5);

// gradienttile.frag's homes (x, y as shares of the tile; a flipped seed
// mirrors x, except for the third, which sits mid-bottom) and reaches.
export const HOMES = [0.1, 0.1, 0.9, 0.3, 0.45, 1.0, 0.62, 0.62];
export const REACH = [0.1, 0.18, 0.12, 0.2, 0.18, 0.15, 0.2, 0.22];

export type MeshLayout = {
  centres: Float32Array; // four colour fields, x y each, in CSS px
  ring1: Float32Array; // x, y, radius, on
  ring2: Float32Array;
  inv: number; // the fields' 1 / spread²
};

export const newMeshLayout = (): MeshLayout => ({
  centres: new Float32Array(8),
  ring1: new Float32Array(4),
  ring2: new Float32Array(4),
  inv: 0,
});

// Where everything is at time `t` (radians of the tile's loop) on a w x h
// tile: gradienttile.frag's homes and reaches, with wandering paths. Written
// into `out`, so the running loop allocates nothing.
export function meshLayout(t: number, w: number, h: number, seed: number, rings: number, out = newMeshLayout()): MeshLayout {
  const s = seed;
  const flip = wrap(s * 0.618034) >= 0.5;
  for (let k = 0; k < 4; k++) {
    const hx = flip && k !== 2 ? 1 - HOMES[k * 2] : HOMES[k * 2];
    out.centres[k * 2] = w * (hx + axis(t, s, k * 2, REACH[k * 2]));
    out.centres[k * 2 + 1] = h * (HOMES[k * 2 + 1] + axis(t, s, k * 2 + 1, REACH[k * 2 + 1]));
  }

  const R1 = Math.min(0.4 * w, 1.05 * h);
  const homeX = w * (flip ? 1 - 0.72 : 0.72);
  const homeY = h * 0.42;
  const side = flip ? 1 : -1;
  const ax = 0.3 * R1 + 0.05 * w;
  const r1 = out.ring1;
  r1[0] = homeX + axis(t, s, 8, ax);
  r1[1] = homeY + axis(t, s, 9, 0.22 * R1);
  r1[2] = R1;
  r1[3] = rings >= 1 ? 1 : 0;
  const r2 = out.ring2;
  r2[0] = homeX + 0.55 * side * R1 + axis(t, s, 10, ax);
  r2[1] = homeY + 0.62 * R1 + axis(t, s, 11, 0.26 * R1);
  r2[2] = 0.72 * R1;
  r2[3] = rings >= 2 ? 1 : 0;
  const S = Math.sqrt(w * h);
  out.inv = 1 / (0.34 * S * S);
  return out;
}
