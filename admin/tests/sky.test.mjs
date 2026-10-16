// The sky backdrops (lib/sky.ts, components/sky-shaders.ts): the numbers
// have to stay Backdrop.qml's (display/qml/components/Backdrop.qml), the
// fourth stop Theme.qml's cream, and the shaders the display's .frag files
// line for line.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import {
  SKY_CREAM,
  SKY_LOOKS,
  SKY_STYLES,
  blendStops,
  displayBackdrop,
  hexRgb,
  labToLch,
  skyStops,
  skyStrength,
  srgbToOklab,
  unwrapHues,
} from "../lib/sky.ts";
import { SKY_FUNCTIONS, SKY_SCENES, skyFragment } from "../components/sky-shaders.ts";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const near = (a, b, eps = 1e-6) => Math.abs(a - b) < eps;

// The text from `signature` to the closing brace of its body.
function block(src, signature) {
  const start = src.indexOf(signature);
  assert.notEqual(start, -1, signature);
  let i = src.indexOf("{", start);
  let depth = 0;
  for (; i < src.length; i++) {
    if (src[i] === "{") depth++;
    else if (src[i] === "}" && --depth === 0) break;
  }
  return src.slice(start, i + 1);
}

test("each style's strength and resolution are Backdrop.qml's", () => {
  const qml = read("../../display/qml/components/Backdrop.qml");
  const looks = block(qml, "readonly property var _looks:");
  const rows = [...looks.matchAll(/"(\w+)":\s*\{\s*strength:\s*\[([\d.]+),\s*([\d.]+)\],\s*resolution:\s*([\d.]+)\s*\}/g)];
  assert.deepEqual(
    rows.map((r) => r[1]).sort(),
    [...SKY_STYLES].sort(),
    "the styles",
  );
  for (const [, style, day, night, resolution] of rows) {
    assert.deepEqual([...SKY_LOOKS[style].strength], [Number(day), Number(night)], `${style} strength`);
    assert.equal(SKY_LOOKS[style].resolution, Number(resolution), `${style} resolution`);
  }
});

test("the strength rises from the day's to the night's, clamped, times brightness", () => {
  for (const style of SKY_STYLES) {
    const [day, night] = SKY_LOOKS[style].strength;
    assert.equal(skyStrength(style, 0), day, `${style} by day`);
    assert.equal(skyStrength(style, 1), night, `${style} at night`);
    assert.ok(near(skyStrength(style, 0.5), (day + night) / 2), `${style} halfway`);
    assert.equal(skyStrength(style, -1), day, "below 0 is the day");
    assert.equal(skyStrength(style, 2), night, "above 1 is the night");
    assert.ok(near(skyStrength(style, 0, 0.5), day * 0.5), "brightness scales it");
    assert.equal(skyStrength(style, 1, 3), 1, "never past 1");
  }
});

test("the fourth stop is Theme.qml's cream for each mood", () => {
  const qml = read("../../display/qml/Theme.qml");
  const palettes = block(qml, "readonly property var palettes:");
  for (const mood of ["morning", "day", "evening", "night"]) {
    const entry = block(palettes, `"${mood}":`);
    const glow = entry.match(/glow:\s*\[([^\]]*)\]/)[1].match(/#[0-9A-Fa-f]{6}/g);
    assert.equal(glow.length, 4, `${mood} has four glow stops on the display`);
    assert.equal(SKY_CREAM[mood], glow[3].toLowerCase(), `${mood} cream`);
  }
});

test("the display's choice: the most recently seen display, mesh without a key, the arc for a stranger", () => {
  const seen = (iso, backdrop, created = "2026-01-01T00:00:00Z") => ({ last_seen_at: iso, created_at: created, settings: backdrop === undefined ? {} : { backdrop } });
  assert.equal(displayBackdrop([]), "mesh", "no display");
  assert.equal(displayBackdrop([seen("2026-10-16T10:00:00Z")]), "mesh", "no key");
  assert.equal(displayBackdrop([seen("2026-10-16T10:00:00Z", "mesh")]), "mesh");
  assert.equal(displayBackdrop([seen("2026-10-16T10:00:00Z", "dawn")]), "dawn");
  assert.equal(displayBackdrop([seen("2026-10-13T10:00:00Z", "silk"), seen("2026-10-16T10:00:00Z", "pillars")]), "pillars", "the latest wins");
  assert.equal(displayBackdrop([seen("2026-10-16T10:00:00Z", "ribbons"), seen("2026-10-13T10:00:00Z", "silk")]), "ribbons", "whatever the order");
  assert.equal(displayBackdrop([seen(null, "silk"), seen("2026-10-13T10:00:00Z", "arc")]), "arc", "a display never seen comes last");
  assert.equal(displayBackdrop([seen(null, "silk", "2026-03-01T00:00:00Z"), seen(null, "dawn", "2026-05-01T00:00:00Z")]), "dawn", "none seen: the newest");
  assert.equal(displayBackdrop([seen("2026-10-16T10:00:00Z", "veil")]), "arc", "a name this build doesn't know");
  assert.equal(displayBackdrop([{ last_seen_at: "2026-10-16T10:00:00Z", created_at: "2026-01-01T00:00:00Z", settings: null }]), "mesh", "no settings at all");
});

test("sRGB to OKLCh, as Theme.qml's oklab()", () => {
  const white = labToLch(srgbToOklab(hexRgb("#ffffff")));
  assert.ok(near(white[0], 1, 1e-3), "white is lightness 1");
  assert.ok(white[1] < 1e-3, "white has no chroma");
  const grey = labToLch(srgbToOklab(hexRgb("#808080")));
  assert.ok(grey[1] < 1e-3, "grey has no chroma");
  const red = labToLch(srgbToOklab(hexRgb("#ff0000")));
  assert.ok(near(red[0], 0.6279554, 1e-5), "red's lightness");
  assert.ok(near(red[1], 0.2576833, 1e-5), "red's chroma");
  assert.ok(near(red[2], (29.2338851 * Math.PI) / 180, 1e-5), "red's hue");
  assert.deepEqual(hexRgb("#fff"), [1, 1, 1], "short hex");
  assert.deepEqual(hexRgb(" #000000 "), [0, 0, 0], "spaces around");
});

test("hues are unwrapped toward the stop before, the short way round", () => {
  const d = (deg) => (deg * Math.PI) / 180;
  const stops = [
    [0.7, 0.1, d(350)],
    [0.7, 0.1, d(10)],
    [0.7, 0.1, d(200)],
    [0.7, 0.1, d(-170)],
  ];
  const out = unwrapHues(stops);
  assert.ok(near(out[1][2], d(370)), "350° then 10° goes on to 370°");
  assert.ok(near(out[2][2], d(200)), "370° then 200° comes back");
  assert.ok(near(out[3][2], d(190)), "-170° is 190°, a step from 200°");
  for (let i = 1; i < out.length; i++) assert.ok(Math.abs(out[i][2] - out[i - 1][2]) <= Math.PI + 1e-9, `step ${i} is the short way`);
  for (let i = 0; i < out.length; i++) {
    assert.equal(out[i][0], stops[i][0], "lightness kept");
    assert.equal(out[i][1], stops[i][1], "chroma kept");
  }
});

test("a grey stop takes its neighbour's hue, and a grey first stop the first known one", () => {
  const d = (deg) => (deg * Math.PI) / 180;
  const out = unwrapHues([
    [0.5, 0.01, d(0)],
    [0.7, 0.1, d(120)],
    [0.6, 0.0, d(-90)],
    [0.7, 0.1, d(130)],
  ]);
  assert.ok(near(out[0][2], d(120)), "the grey first stop sits at the first known hue");
  assert.ok(near(out[2][2], d(120)), "a grey in the middle keeps the hue before it");
  assert.ok(near(out[3][2], d(130)));
  const greys = unwrapHues([[0.5, 0, 1], [0.6, 0, 2]]);
  assert.deepEqual(greys.map((s) => s[2]), [0, 0], "all grey: hue 0");
});

test("skyStops gives the shader four stops, padding with the last", () => {
  const blue = hexRgb("#5b7cf5");
  const coral = hexRgb("#f07f5a");
  const amber = hexRgb("#f6b94a");
  const cream = hexRgb("#fbe6b0");
  const four = skyStops([blue, coral, amber, cream]);
  assert.equal(four.length, 4);
  const want = [blue, coral, amber, cream].map((c) => labToLch(srgbToOklab(c)));
  for (let i = 0; i < 4; i++) {
    assert.ok(near(four[i][0], want[i][0]), `stop ${i} lightness`);
    assert.ok(near(four[i][1], want[i][1]), `stop ${i} chroma`);
    assert.ok(near(Math.atan2(Math.sin(four[i][2]), Math.cos(four[i][2])), want[i][2]), `stop ${i} hue, modulo a turn`);
  }
  const three = skyStops([blue, coral, amber]);
  assert.deepEqual(three[3], three[2], "three: the last repeated");
  const five = skyStops([blue, coral, amber, cream, blue]);
  assert.equal(five.length, 4, "a fifth is dropped");
  assert.equal(skyStops([]).length, 4, "none: still four");
});

test("a palette glides to the next with the hue going the short way", () => {
  const d = (deg) => (deg * Math.PI) / 180;
  const from = [[0.6, 0.1, d(350)], [0.6, 0.1, d(350)], [0.6, 0.1, d(350)], [0.6, 0.1, d(350)]];
  const to = [[0.8, 0.2, d(10)], [0.8, 0.2, d(10)], [0.8, 0.2, d(10)], [0.8, 0.2, d(10)]];
  const start = blendStops(from, to, 0);
  const half = blendStops(from, to, 0.5);
  const end = blendStops(from, to, 1);
  assert.ok(near(start[0][0], 0.6) && near(start[0][1], 0.1), "t 0 is the old palette");
  assert.ok(near(end[0][0], 0.8) && near(end[0][1], 0.2), "t 1 is the new one");
  assert.ok(near(half[0][0], 0.7) && near(half[0][1], 0.15), "halfway in lightness and chroma");
  assert.ok(near(Math.cos(half[0][2]), 1, 1e-9), "halfway from 350° to 10° is 0°, not 180°");
  // A grey partner takes the other's hue, so a stop fading in from grey doesn't spin.
  const fromGrey = blendStops([[0.5, 0, 0], [0.5, 0, 0], [0.5, 0, 0], [0.5, 0, 0]], to, 0.5);
  assert.ok(near(Math.cos(fromGrey[0][2] - d(10)), 1, 1e-9), "the hue is the new one all along");
});

test("the scene bodies are the display's, line for line", () => {
  for (const style of SKY_STYLES) {
    const frag = read(`../../display/shaders/${style}.frag`);
    assert.equal(SKY_SCENES[style], block(frag, "void scene("), style);
  }
});

test("the shared functions are the display's, line for line", () => {
  for (const style of SKY_STYLES) {
    const frag = read(`../../display/shaders/${style}.frag`);
    for (const name of ["vec3 permute(", "float snoise(", "float hash(", "float tri(", "vec3 lch2lab(", "vec3 ramp(", "vec3 oklabToSrgb("]) {
      if (!frag.includes(name)) continue; // silk has no noise, only ribbons has tri
      assert.equal(block(SKY_FUNCTIONS, name), block(frag, name), `${style} ${name}`);
    }
  }
});

test("each fragment shader is GLSL ES 1.00 with the display's uniforms", () => {
  for (const style of SKY_STYLES) {
    const src = skyFragment(style);
    assert.ok(!src.includes("#version"), "no version line: ES 1.00");
    assert.ok(src.includes("gl_FragColor"), "writes gl_FragColor");
    assert.ok(!/\bin\s+vec|\bout\s+vec4\s+\w+;/.test(src), "no ES 3.00 in/out variables");
    for (const u of ["vec2 size", "float time", "float strength", "float seed", "float dim", "vec4 canvas", "vec4 s0", "vec4 s1", "vec4 s2", "vec4 s3"])
      assert.ok(src.includes(`uniform ${u};`), `${style} declares ${u}`);
    assert.ok(src.includes(SKY_SCENES[style]), `${style} holds its scene`);
    assert.equal((src.match(/void main\(\)/g) ?? []).length, 1, "one main");
    // The lay-on is the display's: strength scales the picture, an OKLab mix lands it on the canvas, then the dither.
    assert.ok(src.includes("a = clamp(a, 0.0, 1.0) * strength;"));
    assert.ok(src.includes("oklabToSrgb(mix(canvas.xyz, lab, a))"));
    assert.ok(src.includes("(hash(cell) + hash(cell + 17.13) - 1.0) / 255.0 / max(dim, 0.1)"));
  }
});
