// MeshGradient's colour and motion (lib/mesh.ts): the palette has to stay
// GradientTile.qml's (display/qml/components/GradientTile.qml, the pastel
// and night mappings), and the drifting fields have to move smoothly and
// stay on their tile however far the wall clock has run.
import assert from "node:assert/strict";
import { test } from "node:test";
import { HOMES, REACH, meshLayout, meshPalette, newMeshLayout, srgbToOklab } from "../lib/mesh.ts";

const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255);

// OKLab back to sRGB, then to HSL: the inverse of what meshPalette does last.
function oklabToSrgb([L, a, b]) {
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
  const lin = [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  ];
  return lin.map((c) => (c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055));
}
function hsl([r, g, b]) {
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  const d = max - min;
  if (d < 1e-6) return { h: 0, s: 0, l };
  const s = d / (1 - Math.abs(2 * l - 1));
  const h = max === r ? ((g - b) / d + 6) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return { h: h / 6, s, l };
}
const hslOf = (palette) => palette.map((lab) => hsl(oklabToSrgb(lab)));
const close = (a, b, eps, what) => assert.ok(Math.abs(a - b) < eps, `${what}: ${a} vs ${b}`);
// Hue distance on the circle, signed, in turns.
const turn = (a, b) => ((a - b + 1.5) % 1) - 0.5;

test("the glow tokens become GradientTile's pastels by day and deep tones at night", () => {
  const glow = ["#5b7cf5", "#f07f5a", "#f6b94a"].map(hex);
  const day = hslOf(meshPalette(glow, false));
  const night = hslOf(meshPalette(glow, true));
  assert.equal(day.length, 4);
  [0.79, 0.83, 0.76, 0.94].forEach((l, i) => close(day[i].l, l, 1e-6, `day L${i}`));
  [0.19, 0.22, 0.15, 0.27].forEach((l, i) => close(night[i].l, l, 1e-6, `night L${i}`));
  // Same hues, quieter at night; the saturation clamped into the pastel range.
  const source = glow.map(hsl);
  for (let i = 0; i < 3; i++) {
    close(turn(day[i].h, source[i].h), 0, 1e-6, `day hue ${i}`);
    close(turn(night[i].h, source[i].h), 0, 1e-6, `night hue ${i}`);
    assert.ok(day[i].s >= 0.38 - 1e-6 && day[i].s <= 0.78 + 1e-6, `pastel s${i} = ${day[i].s}`);
    assert.ok(night[i].s < day[i].s);
  }
  // Three colours: the highlight is the first, nudged round by 0.03.
  close(turn(day[3].h, source[0].h), 0.03, 1e-6, "highlight hue");
});

test("one colour: its analogous hues, narrower at night so warm tiles don't go olive", () => {
  const base = hsl(hex("#E2725B"));
  const day = hslOf(meshPalette([hex("#E2725B")], false));
  const night = hslOf(meshPalette([hex("#E2725B")], true));
  [0, 0.075, -0.085, 0.03].forEach((dh, i) => close(turn(day[i].h, base.h), dh, 1e-6, `day hue ${i}`));
  [0, 0.03, -0.035, 0].forEach((dh, i) => close(turn(night[i].h, base.h), dh, 1e-6, `night hue ${i}`));
  [0.79, 0.83, 0.76, 0.94].forEach((l, i) => close(day[i].l, l, 1e-6, `day L${i}`));
  [0.19, 0.22, 0.15, 0.27].forEach((l, i) => close(night[i].l, l, 1e-6, `night L${i}`));
  // A grey stays grey; four colours are taken as they are.
  for (const c of hslOf(meshPalette([hex("#808080")], false))) assert.ok(c.s < 0.02, `grey s ${c.s}`);
  const four = hslOf(meshPalette(["#3b4fb8", "#7a64e8", "#a04e78", "#14c2c2"].map(hex), false));
  close(turn(four[3].h, hsl(hex("#14c2c2")).h), 0, 1e-6, "fourth hue");
  // OKLab of white is L 1, no chroma.
  const white = srgbToOklab([1, 1, 1]);
  close(white[0], 1, 1e-6, "white L");
  close(Math.hypot(white[1], white[2]), 0, 1e-6, "white chroma");
});

test("the fields move smoothly however far the wall clock has run", () => {
  // MeshGradient's clock starts from Date.now(): about 2e8 radians of loop.
  const w = 1484;
  const h = 940;
  for (const seed of [0, 1, 3, 7]) {
    for (const t of [2e8, 2.3e8 + 0.5, 2.6e8 + 1.25]) {
      const a = meshLayout(t, w, h, seed, 2);
      const b = meshLayout(t + 1e-3, w, h, seed, 2);
      let moved = 0;
      for (const k of ["centres", "ring1", "ring2"]) {
        for (let j = 0; j < a[k].length; j++) {
          assert.ok(Number.isFinite(a[k][j]), `${k}[${j}] finite`);
          const d = Math.abs(a[k][j] - b[k][j]);
          // A thousandth of a radian (a quarter of a frame at 30 fps) moves
          // nothing more than a pixel.
          assert.ok(d < 1, `seed ${seed} t ${t} ${k}[${j}] jumped ${d}px`);
          moved = Math.max(moved, d);
        }
      }
      assert.ok(moved > 1e-4, "something moves");
    }
  }
});

test("every centre stays within its home and reach", () => {
  for (const [w, h] of [
    [480, 290],
    [1484, 940],
    [200, 900],
  ]) {
    for (const seed of [0, 1, 2, 3, 7, 0.5]) {
      const flip = seed * 0.618034 - Math.floor(seed * 0.618034) >= 0.5;
      const out = newMeshLayout();
      for (let i = 0; i < 2000; i++) {
        const t = i * 0.731 + (i % 13) * 1.7e8;
        const l = meshLayout(t, w, h, seed, 2, out);
        assert.equal(l, out, "written into out");
        for (let k = 0; k < 4; k++) {
          const hx = flip && k !== 2 ? 1 - HOMES[k * 2] : HOMES[k * 2];
          const x = l.centres[k * 2] / w;
          const y = l.centres[k * 2 + 1] / h;
          assert.ok(Math.abs(x - hx) <= REACH[k * 2] + 1e-6, `x${k} ${x} vs ${hx}±${REACH[k * 2]}`);
          assert.ok(Math.abs(y - HOMES[k * 2 + 1]) <= REACH[k * 2 + 1] + 1e-6, `y${k} ${y}`);
        }
        // The glass rings sit around their own home, the second off the first.
        const R1 = Math.min(0.4 * w, 1.05 * h);
        const homeX = w * (flip ? 0.28 : 0.72);
        assert.ok(Math.abs(l.ring1[0] - homeX) <= 0.3 * R1 + 0.05 * w + 1e-3);
        assert.ok(Math.abs(l.ring1[1] - h * 0.42) <= 0.22 * R1 + 1e-3);
        assert.ok(Math.abs(l.ring1[2] - R1) < 1e-3); // Float32
        assert.ok(Math.abs(l.ring2[2] - 0.72 * R1) < 1e-3);
        assert.deepEqual([l.ring1[3], l.ring2[3]], [1, 1]);
      }
      assert.deepEqual([meshLayout(1, w, h, seed, 0).ring1[3], meshLayout(1, w, h, seed, 1).ring2[3]], [0, 0]);
    }
  }
});
