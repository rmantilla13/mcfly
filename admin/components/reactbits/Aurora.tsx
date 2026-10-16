/*
 * Aurora, from React Bits (https://github.com/DavidHDev/react-bits,
 * src/ts-tailwind/Backgrounds/Aurora, commit 963f4d2), ported for McFly.
 * The display has the same shader for Qt: display/shaders/aurora.frag.
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
 * Changes for McFly: each mount makes its own canvas (the cleanup loses the
 * WebGL context, so a remount reusing the old canvas drew nothing); props reach
 * the render loop from an effect (not during render), and only when one
 * changed; `maxFps` caps the redraws, sleeping on a timer between them as
 * MeshGradient does; with reduced motion it draws one still frame and stops instead of
 * redrawing a frozen picture every frame; `glowStops` reads McFly's --glow-*
 * tokens, since a CSS variable isn't a canvas colour.
 *
 * Then a second pass, the same in both ports: the hem folds through a 2D
 * domain warp instead of sliding along X; faint rays run down the curtain
 * (`rays`); the hue sways on smooth noise; triangular dither, sized to the
 * final opacity; light mode is ink on the canvas, eased in and out; a new
 * palette glides in over 1.5 s in OKLCh; the clock starts from the wall
 * clock, so no two mounts open on the same curtain; the lowering intro only
 * runs when `intro` asks for it (otherwise it fades in); and `resolution`
 * renders at a fraction of the device's pixel ratio.
 */
"use client";

import { useEffect, useRef, type CSSProperties } from "react";

export interface AuroraProps {
  colorStops?: string[];
  amplitude?: number;
  blend?: number;
  speed?: number;
  time?: number;
  height?: number;
  scale?: number;
  glow?: number;
  brightness?: number;
  layers?: number;
  direction?: "top" | "bottom";
  mouseInteraction?: boolean;
  intro?: boolean; // lower the curtain into place on mount; otherwise it fades in
  opacity?: number;
  lightMode?: boolean; // ink on a light canvas instead of light on a dark one (eased)
  rays?: number; // 0..1, faint vertical rays in the curtain; 0 skips their noise
  paused?: boolean;
  resolution?: number; // fraction of the device pixel ratio to render at (capped at 2x)
  dpr?: number; // absolute pixel ratio; `resolution` wins when both are set
  maxFps?: number; // 0: every frame
  className?: string;
  style?: CSSProperties;
}

type Settings = {
  stops: string[];
  amplitude: number;
  blend: number;
  speed: number;
  time?: number;
  height: number;
  scale: number;
  glow: number;
  brightness: number;
  layers: number;
  flip: number;
  mouseInteraction: boolean;
  intro: boolean;
  opacity: number;
  lightMode: boolean;
  rays: number;
  paused: boolean;
  resolution?: number;
  dpr?: number;
  maxFps: number;
};

type Program = { program: WebGLProgram; uniforms: Record<string, WebGLUniformLocation | null> };
type Lch = number[]; // OKLCh: lightness, chroma, hue in radians

const MAX_STOPS = 5;
const MAX_LAYERS = 3;
const INTRO_SECONDS = 2.4;
const APPEAR_SECONDS = 1.2;
const PALETTE_SECONDS = 1.5;
const LIGHT_SECONDS = 0.2; // time constant: light mode settles in about 600 ms

const VERTEX = `#version 300 es
in vec2 aPosition;
void main() {
  gl_Position = vec4(aPosition, 0.0, 1.0);
}`;

// Kept line for line with display/shaders/aurora.frag; the differences are
// the host's: pixel coordinates, the pointer's pull, uniform names, opacity.
const FRAGMENT = `#version 300 es
precision highp float;
precision highp int;
uniform vec2 uResolution;
uniform float uTime;
uniform vec3 uStops[${MAX_STOPS}];
uniform int uStopCount;
uniform float uAmplitude;
uniform float uBlend;
uniform float uHeight;
uniform float uScale;
uniform float uGlow;
uniform float uBrightness;
uniform int uLayers;
uniform float uFlip;
uniform vec3 uPointer;
uniform float uReveal;
uniform float uOpacity;
uniform float uLightMode;
uniform float uRays;
uniform vec3 uDrift;
out vec4 outColor;

vec3 permute(vec3 x) {
  return mod(((x * 34.0) + 1.0) * x, 289.0);
}

float snoise(vec2 v) {
  const vec4 C = vec4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
  vec2 i = floor(v + dot(v, C.yy));
  vec2 x0 = v - i + dot(i, C.xx);
  vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  vec4 x12 = x0.xyxy + C.xxzz;
  x12.xy -= i1;
  i = mod(i, 289.0);
  vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
  vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
  m = m * m;
  m = m * m;
  vec3 x = 2.0 * fract(p * C.www) - 1.0;
  vec3 h = abs(x) - 0.5;
  vec3 ox = floor(x + 0.5);
  vec3 a0 = x - ox;
  m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
  vec3 g;
  g.x = a0.x * x0.x + h.x * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}

float smootherstep(float edge0, float edge1, float x) {
  float t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
  return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

vec3 oklabToLinear(vec3 c) {
  float l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
  float m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
  float s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
  l = l * l * l;
  m = m * m * m;
  s = s * s * s;
  return vec3(
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
  );
}

vec3 toSrgb(vec3 c) {
  c = clamp(c, 0.0, 1.0);
  return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

// The pair of stops either side of t is picked by comparison, not by a
// computed index: GLSL ES 1.00 (the display's) only promises constant ones.
vec3 ramp(float t) {
  float n = clamp(float(uStopCount), 2.0, 5.0);
  float x = clamp(t, 0.0, 1.0) * (n - 1.0);
  float i = min(floor(x), n - 2.0);
  float f = x - i;
  f = f * f * (3.0 - 2.0 * f);
  vec3 a = uStops[0];
  vec3 b = uStops[1];
  if (i > 0.5) { a = uStops[1]; b = uStops[2]; }
  if (i > 1.5) { a = uStops[2]; b = uStops[3]; }
  if (i > 2.5) { a = uStops[3]; b = uStops[4]; }
  vec3 lch = mix(a, b, f);
  return toSrgb(oklabToLinear(vec3(lch.x, lch.y * cos(lch.z), lch.y * sin(lch.z))));
}

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

void main() {
  vec2 frag = gl_FragCoord.xy;
  float y = 1.0 - frag.y / uResolution.y;
  y = mix(y, 1.0 - y, uFlip);
  float u = frag.x / uResolution.x;
  float X = (frag.x - uResolution.x * 0.5) / uResolution.y;
  float t = uTime;
  float reach = uPointer.z * exp(-pow((X - uPointer.x) / 0.38, 2.0));

  vec3 light = vec3(0.0); // over a dark sky: the layers screened, premultiplied
  float cover = 0.0;
  vec3 ink = vec3(1.0); // on a light canvas: what the layers let through, multiplied
  for (int k = 0; k < ${MAX_LAYERS}; k++) {
    if (k >= uLayers) break;
    float layer = float(k);
    float seed = layer * 13.7;
    float pace = t * (1.0 - layer * 0.18);
    // A slow 2D warp that the hem folds through: it bends the waves in place
    // and in time, so nothing slides along X at a steady rate.
    vec2 q = vec2(X * 0.45 * uScale, pace * 0.035 + seed);
    vec2 w = vec2(snoise(q), snoise(q + vec2(5.2, 1.3)));
    float wave = snoise(vec2(X * 0.75 * uScale, pace * 0.05 - seed) + w * 0.35) * 0.72
      + snoise(vec2(X * 1.6 * uScale, pace * 0.09 + seed * 0.5) + w * 0.5) * 0.28;
    float edge = uHeight + layer * 0.07 + wave * 0.15 * uAmplitude;
    edge += reach * 0.08 * (layer < 0.5 ? 1.0 : 0.4);
    edge = mix(-0.25, edge, uReveal);

    float soft = (0.04 + uBlend * 0.16) * (1.0 + layer * 0.9);
    float rise = edge - y;
    float low = -soft - uGlow * 0.14;
    float high = 0.26 + soft * 0.6;
    float body = pow(smootherstep(low, high, rise), 1.5 + uGlow * 0.6);
    float alpha = body * (0.86 + 0.14 * w.y) * (layer < 0.5 ? 1.0 : 0.32 / layer);
    // Rays: soft streaks along the fall of the curtain (a noise stretched
    // tall), bent by the same warp, gathered where the warp says, and
    // strongest just above the hem. They only take light away.
    if (uRays > 0.0) {
      float n = snoise(vec2(X * 7.0 * uScale + w.x * 2.0, y * 0.5 + pace * 0.1 - seed));
      float along = smootherstep(-0.1, 0.1, rise) * (1.0 - 0.6 * smootherstep(0.1, 0.5, rise));
      float gather = smootherstep(-0.3, 0.5, w.y);
      alpha *= 1.0 - uRays * 0.22 * n * n * along * gather;
    }
    alpha = clamp(alpha * (1.0 + reach * 0.25 * smootherstep(0.9, 0.0, abs(y - edge))), 0.0, 1.0);

    float sway = layer < 0.5 ? uDrift.x : (layer < 1.5 ? uDrift.y : uDrift.z);
    vec3 tint = ramp(u + sway + layer * 0.1 + max(rise, 0.0) * 0.05);
    light = 1.0 - (1.0 - light) * (1.0 - tint * alpha);
    cover = 1.0 - (1.0 - cover) * (1.0 - alpha);
    // As ink the colour is a filter: its own channel passes in full, so the
    // canvas is tinted, never greyed.
    ink *= 1.0 - alpha * (1.0 - tint / max(max(tint.r, tint.g), max(tint.b, 0.001)));
  }

  float strength = clamp(uBrightness, 0.0, 2.0);
  float gain = smootherstep(0.0, 0.7, uReveal) * min(strength, 1.0);
  vec4 onDark = vec4(1.0 - pow(1.0 - light * gain, vec3(max(strength, 1.0))), cover * gain);
  // Ink laid on with a plain "over": the alpha is the most a channel absorbs
  // and the colour what the others keep, which on a light canvas comes out
  // as a multiply. A faint tail is held back so the page isn't stained.
  vec3 absorb = (1.0 - pow(ink, vec3(max(strength, 1.0)))) * gain * smootherstep(0.0, 0.25, cover * gain) * 0.7;
  float inked = max(absorb.r, max(absorb.g, absorb.b));
  vec4 col = mix(onDark, vec4(inked - absorb, inked), uLightMode);

  // Triangular dither, one step of the final picture: the opacity comes
  // after it, so it is scaled up by as much. Only where there is light.
  vec2 cell = floor(frag);
  float dither = (hash(cell) + hash(cell + 17.13) - 1.0) / 255.0;
  col += dither / max(uOpacity, 0.1) * min(col.a * 255.0, 1.0);
  outColor = clamp(col, 0.0, 1.0) * uOpacity;
}`;

const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));

// McFly's glow (--glow-1, -2, -3 in globals.css: blue, coral, amber) as
// colours a canvas can read, blue at both ends so the curtain closes on itself.
export function glowStops(): string[] {
  const css = getComputedStyle(document.documentElement);
  const [blue, coral, amber] = ["--glow-1", "--glow-2", "--glow-3"].map((name) => css.getPropertyValue(name).trim());
  return blue && coral && amber ? [blue, coral, amber, blue] : ["#5b7cf5", "#f07f5a", "#f6b94a", "#5b7cf5"];
}

const toOklch = (rgb: number[]): Lch => {
  const [r, g, b] = rgb.map((c) => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)));
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  const lab = [
    0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
  ];
  return [lab[0], Math.hypot(lab[1], lab[2]), Math.atan2(lab[2], lab[1])];
};

const unwrapHues = (stops: Lch[]): Lch[] => {
  const known = stops.findIndex((stop) => stop[1] > 0.02);
  const anchor = known === -1 ? 0 : stops[known][2];
  let previous = anchor;
  return stops.map((stop) => {
    let hue = stop[1] > 0.02 ? stop[2] : previous;
    while (hue - previous > Math.PI) hue -= Math.PI * 2;
    while (hue - previous < -Math.PI) hue += Math.PI * 2;
    previous = hue;
    return [stop[0], stop[1], hue];
  });
};

// One palette part way to another, stop by stop in OKLCh: lightness and
// chroma straight across, the hue the short way round (a grey stop takes its
// partner's hue). AuroraGlow.qml eases its palette the same way.
const blendPalettes = (from: Lch[], to: Lch[], t: number): Lch[] =>
  unwrapHues(
    to.map((b, index) => {
      const a = from[index] ?? b;
      const ha = a[1] > 0.02 ? a[2] : b[2];
      const hb = b[1] > 0.02 ? b[2] : ha;
      const turn = hb - ha - Math.PI * 2 * Math.round((hb - ha) / (Math.PI * 2));
      return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, ha + turn * t];
    }),
  );

const samePalette = (a: Lch[], b: Lch[]) =>
  a.length === b.length && a.every((stop, index) => stop.every((value, k) => Math.abs(value - b[index][k]) < 1e-4));

const easeInOutSine = (t: number) => 0.5 - 0.5 * Math.cos(Math.PI * clamp(t, 0, 1));

// The hue's slow sway, per layer: two octaves of smooth 1D gradient noise on
// the layer's own clock. It is the same for every pixel, so it's worked out
// here once a frame rather than in the shader. AuroraGlow.qml has the same.
const lattice = (i: number) => {
  const s = Math.sin(i * 127.1 + 311.7) * 43758.5453;
  return (s - Math.floor(s)) * 2 - 1;
};
const noise1 = (x: number) => {
  const i = Math.floor(x);
  const f = x - i;
  const s = f * f * f * (f * (f * 6 - 15) + 10);
  return 2 * (lattice(i) * f * (1 - s) + lattice(i + 1) * (f - 1) * s);
};
const hueDrift = (time: number, layer: number) => {
  const pace = time * (1 - layer * 0.18);
  return 0.07 * (0.7 * noise1(pace * 0.03 + layer * 3.1) + 0.3 * noise1(pace * 0.071 + 7.7 + layer * 1.3));
};

const compile = (gl: WebGL2RenderingContext, type: number, source: string) => {
  const shader = gl.createShader(type);
  if (!shader) return null;
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (gl.getShaderParameter(shader, gl.COMPILE_STATUS)) return shader;
  gl.deleteShader(shader);
  return null;
};

const link = (gl: WebGL2RenderingContext): Program | null => {
  const vertex = compile(gl, gl.VERTEX_SHADER, VERTEX);
  const fragment = compile(gl, gl.FRAGMENT_SHADER, FRAGMENT);
  const program = gl.createProgram();
  if (!vertex || !fragment || !program) return null;
  gl.attachShader(program, vertex);
  gl.attachShader(program, fragment);
  gl.bindAttribLocation(program, 0, "aPosition");
  gl.linkProgram(program);
  gl.deleteShader(vertex);
  gl.deleteShader(fragment);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    gl.deleteProgram(program);
    return null;
  }
  const uniforms: Record<string, WebGLUniformLocation | null> = {};
  const count = gl.getProgramParameter(program, gl.ACTIVE_UNIFORMS);
  for (let i = 0; i < count; i++) {
    const info = gl.getActiveUniform(program, i);
    if (info) uniforms[info.name.replace("[0]", "")] = gl.getUniformLocation(program, info.name);
  }
  return { program, uniforms };
};

const Aurora = ({
  colorStops = ["#5227FF", "#7cff67", "#5227FF"],
  amplitude = 1,
  blend = 0.5,
  speed = 1,
  time,
  height = 0.45,
  scale = 1,
  glow = 0.6,
  brightness = 1,
  layers = 1,
  direction = "top",
  mouseInteraction = true,
  intro = false,
  opacity = 1,
  lightMode = false,
  rays = 1,
  paused = false,
  resolution,
  dpr,
  maxFps = 0,
  className = "",
  style,
}: AuroraProps) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const wakeRef = useRef<(() => void) | null>(null);
  const stops = (Array.isArray(colorStops) ? colorStops : []).filter(Boolean).map(String).slice(0, MAX_STOPS);
  const settings: Settings = {
    stops: stops.length >= 2 ? stops : stops.length === 1 ? [stops[0], stops[0]] : ["#5227FF", "#7cff67"],
    amplitude: Math.max(0, amplitude),
    blend: clamp(blend, 0, 1),
    speed,
    time,
    height: clamp(height, 0, 1),
    scale: Math.max(0.1, scale),
    glow: Math.max(0, glow),
    brightness: Math.max(0, brightness),
    layers: clamp(Math.round(layers), 1, MAX_LAYERS),
    flip: direction === "bottom" ? 1 : 0,
    mouseInteraction,
    intro,
    opacity: clamp(opacity, 0, 1),
    lightMode,
    rays: clamp(rays, 0, 1),
    paused,
    resolution: resolution === undefined ? undefined : Math.max(0.1, resolution),
    dpr,
    maxFps: Math.max(0, maxFps),
  };
  const settingsRef = useRef(settings);

  // New props reach the running loop here, and an idle loop redraws once,
  // only when one of them changed: a parent that re-renders every second
  // (Ambient's clock) must not redraw a paused aurora every second.
  const keyRef = useRef("");
  useEffect(() => {
    settingsRef.current = settings;
    const key = JSON.stringify(settings);
    if (key === keyRef.current) return;
    keyRef.current = key;
    wakeRef.current?.();
  });

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return undefined;
    // A canvas of its own per mount: the cleanup below loses its context, and
    // a remount (React runs effects twice in development) must not reuse it.
    const canvas = document.createElement("canvas");
    canvas.className = "absolute inset-0 block h-full w-full";
    canvas.setAttribute("aria-hidden", "true");
    const gl = canvas.getContext("webgl2", {
      alpha: true,
      premultipliedAlpha: true,
      antialias: false,
      depth: false,
      stencil: false,
    });
    const program = gl ? link(gl) : null;
    if (!gl || !program) {
      gl?.getExtension("WEBGL_lose_context")?.loseContext();
      return undefined;
    }
    container.appendChild(canvas);
    const u = program.uniforms;

    const buffer = gl.createBuffer();
    const vao = gl.createVertexArray();
    gl.bindVertexArray(vao);
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);

    const probe = document.createElement("canvas").getContext("2d", { willReadFrequently: true });
    const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
    const parse = (value: string): number[] => {
      if (!probe) return [1, 1, 1];
      probe.clearRect(0, 0, 1, 1);
      probe.fillStyle = "#ffffff";
      probe.fillStyle = value;
      probe.fillRect(0, 0, 1, 1);
      const [r, g, b] = probe.getImageData(0, 0, 1, 1).data;
      return [r / 255, g / 255, b / 255];
    };
    // Each set of stops is parsed once; a change of stops glides from the
    // palette on screen to the new one.
    const palettes = new Map<string, Lch[]>();
    const paletteFor = (stops: string[]) => {
      const key = stops.join("|");
      let palette = palettes.get(key);
      if (!palette) {
        palette = unwrapHues(stops.map((value) => toOklch(parse(value))));
        if (palettes.size >= 16) palettes.clear(); // stops that never settle don't pile up
        palettes.set(key, palette);
      }
      return palette;
    };
    const glide = { key: "", from: [] as Lch[], to: [] as Lch[], mix: 1 };
    const shownPalette = () => (glide.mix < 1 ? blendPalettes(glide.from, glide.to, easeInOutSine(glide.mix)) : glide.to);
    const palette = new Float32Array(MAX_STOPS * 3);
    let paletteDirty = true;
    const retarget = (s: Settings) => {
      const key = s.stops.join("|");
      if (key === glide.key) return;
      const first = !glide.key;
      glide.key = key;
      const next = paletteFor(s.stops);
      // The same colours spelled another way: nothing to glide.
      if (!first && samePalette(next, glide.to)) return;
      // The first palette, less motion, or a different number of stops: no glide.
      const snap = first || reduce || glide.to.length !== next.length;
      glide.from = snap ? next : shownPalette();
      glide.to = next;
      glide.mix = snap ? 1 : 0;
      paletteDirty = true;
    };

    const view = { width: 1, height: 1 };
    const pointer = { x: 0, y: 0, inside: false };
    const start = settingsRef.current;
    retarget(start);
    const state = {
      // From the wall clock, so a remount doesn't open on the same curtain;
      // within the hour, so uTime stays small enough for a 32-bit float to
      // step evenly.
      clock: ((Date.now() / 1000) % 3600) * start.speed,
      px: 0,
      py: 0.5,
      reach: 0,
      reveal: start.intro && !reduce ? 0 : 1,
      appear: start.intro || reduce ? 1 : 0,
      light: start.lightMode ? 1 : 0,
    };
    let raf = 0;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let last = 0;
    let visible = true;

    const render = () => {
      const s = settingsRef.current;
      const t = s.time !== undefined ? s.time * s.speed * 0.1 : state.clock;
      if (paletteDirty) {
        shownPalette().forEach((stop, index) => palette.set(stop, index * 3));
        paletteDirty = false;
      }
      gl.viewport(0, 0, canvas.width, canvas.height);
      gl.useProgram(program.program);
      gl.bindVertexArray(vao);
      gl.uniform2f(u.uResolution, canvas.width, canvas.height);
      gl.uniform1f(u.uTime, t);
      gl.uniform3fv(u.uStops, palette);
      gl.uniform1i(u.uStopCount, glide.to.length);
      gl.uniform1f(u.uAmplitude, s.amplitude);
      gl.uniform1f(u.uBlend, s.blend);
      gl.uniform1f(u.uHeight, s.height);
      gl.uniform1f(u.uScale, s.scale);
      gl.uniform1f(u.uGlow, s.glow);
      gl.uniform1f(u.uBrightness, s.brightness);
      gl.uniform1i(u.uLayers, s.layers);
      gl.uniform1f(u.uFlip, s.flip);
      gl.uniform3f(u.uPointer, state.px, state.py, state.reach);
      gl.uniform1f(u.uReveal, 1 - Math.pow(1 - state.reveal, 3));
      gl.uniform1f(u.uOpacity, s.opacity * easeInOutSine(state.appear));
      gl.uniform1f(u.uLightMode, state.light);
      gl.uniform1f(u.uRays, s.rays);
      gl.uniform3f(u.uDrift, hueDrift(t, 0), hueDrift(t, 1), hueDrift(t, 2));
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    };

    // Light mode, a new palette and the first fade-in ease on real time, also
    // while the curtain itself is paused. True while any is still on its way.
    const settle = (s: Settings, dt: number) => {
      const light = s.lightMode ? 1 : 0;
      state.light += (light - state.light) * (1 - Math.exp(-dt / LIGHT_SECONDS));
      if (reduce || Math.abs(light - state.light) < 0.002) state.light = light;
      if (glide.mix < 1) {
        glide.mix = reduce ? 1 : Math.min(1, glide.mix + dt / PALETTE_SECONDS);
        paletteDirty = true;
      }
      if (state.appear < 1) state.appear = reduce ? 1 : Math.min(1, state.appear + dt / APPEAR_SECONDS);
      return state.light !== light || glide.mix < 1 || state.appear < 1;
    };

    // The frame after the one at `now`, `slot` ms on (MeshGradient's): a
    // capped loop sleeps on a timer until just before its slot and then takes
    // the next refresh, so at 15 frames a second it wakes about 15 times a
    // second rather than at every refresh to skip it.
    const next = (slot: number, now: number) => {
      if (slot >= 14) {
        timer = setTimeout(
          () => {
            timer = undefined;
            raf = requestAnimationFrame(frame);
          },
          Math.max(0, slot - 4 - (performance.now() - now)),
        );
      } else raf = requestAnimationFrame(frame);
    };

    const frame = (now: number) => {
      raf = 0;
      if (!visible || document.hidden) return;
      const s = settingsRef.current;
      const slot = s.maxFps > 0 ? 1000 / s.maxFps : 0;
      // Early for its slot (by more than half a refresh after the timer, or
      // at all for a cap near the refresh rate, which has no timer): skip.
      if (slot && last && now - last < slot - (slot >= 14 ? 8 : 2)) {
        raf = requestAnimationFrame(frame);
        return;
      }
      const longest = s.maxFps > 0 ? Math.max(0.05, 2 / s.maxFps) : 0.05;
      const dt = last ? clamp((now - last) / 1000, 0.0005, longest) : 1 / 60;
      last = now;
      // Paused, or asked for less motion: a still picture (once anything
      // easing has arrived, the loop stops).
      const still = s.paused || reduce;
      if (still) state.reveal = 1;
      else {
        state.clock += dt * s.speed;
        const engaged = s.mouseInteraction && pointer.inside;
        const follow = 1 - Math.exp(-dt / 0.6);
        if (engaged) {
          const tx = (pointer.x - view.width / 2) / view.height;
          const ty = s.flip ? 1 - pointer.y / view.height : pointer.y / view.height;
          state.px += (tx - state.px) * follow;
          state.py += (ty - state.py) * follow;
        }
        state.reach += ((engaged ? 1 : 0) - state.reach) * (1 - Math.exp(-dt / (engaged ? 0.9 : 1.4)));
        if (!s.intro) state.reveal = 1;
        else if (state.reveal < 1) state.reveal = Math.min(1, state.reveal + dt / INTRO_SECONDS);
      }
      const settling = settle(s, dt);
      render();
      if (!still || settling) next(slot, now);
      else last = 0;
    };

    const wake = () => {
      if (!raf && timer === undefined && visible && !document.hidden) raf = requestAnimationFrame(frame);
    };

    // `resolution` is a share of the device's pixels; `dpr` an absolute ratio.
    const pixelRatio = (s: Settings) => {
      const device = window.devicePixelRatio || 1;
      return Math.min(s.resolution !== undefined ? s.resolution * device : s.dpr || device, 2);
    };

    const resize = () => {
      const width = Math.max(1, container.clientWidth);
      const height = Math.max(1, container.clientHeight);
      const ratio = pixelRatio(settingsRef.current);
      view.width = width;
      view.height = height;
      canvas.width = Math.max(1, Math.round(width * ratio));
      canvas.height = Math.max(1, Math.round(height * ratio));
      render();
      wake();
    };

    const onPointerMove = (event: PointerEvent) => {
      const rect = container.getBoundingClientRect();
      pointer.x = event.clientX - rect.left;
      pointer.y = event.clientY - rect.top;
      const wasInside = pointer.inside;
      pointer.inside = pointer.x >= 0 && pointer.y >= 0 && pointer.x <= rect.width && pointer.y <= rect.height;
      if (pointer.inside && !wasInside) {
        const s = settingsRef.current;
        state.px = (pointer.x - rect.width / 2) / Math.max(1, rect.height);
        state.py = s.flip ? 1 - pointer.y / Math.max(1, rect.height) : pointer.y / Math.max(1, rect.height);
      }
      if (!settingsRef.current.paused && !reduce) wake();
    };

    const onPointerUp = (event: PointerEvent) => {
      if (event.pointerType !== "mouse") pointer.inside = false;
    };

    const onPointerLeave = () => {
      pointer.inside = false;
    };

    const onVisibility = () => {
      last = 0;
      wake();
    };

    const resizeObserver = new ResizeObserver(resize);
    resizeObserver.observe(container);
    const intersection = new IntersectionObserver((entries) => {
      visible = entries.some((entry) => entry.isIntersecting);
      if (visible) {
        last = 0;
        wake();
      }
    });
    intersection.observe(container);
    window.addEventListener("pointermove", onPointerMove, { passive: true });
    window.addEventListener("pointerdown", onPointerMove, { passive: true });
    window.addEventListener("pointerup", onPointerUp, { passive: true });
    window.addEventListener("pointercancel", onPointerUp, { passive: true });
    document.documentElement.addEventListener("pointerleave", onPointerLeave);
    document.addEventListener("visibilitychange", onVisibility);
    resize();

    const ratioKey = (s: Settings) => `${s.resolution}|${s.dpr}`;
    let lastRatio = ratioKey(settingsRef.current);
    wakeRef.current = () => {
      const s = settingsRef.current;
      retarget(s);
      if (ratioKey(s) !== lastRatio) {
        lastRatio = ratioKey(s);
        resize();
        return;
      }
      if (!raf && timer === undefined) render();
      wake();
    };

    return () => {
      cancelAnimationFrame(raf);
      clearTimeout(timer);
      wakeRef.current = null;
      resizeObserver.disconnect();
      intersection.disconnect();
      window.removeEventListener("pointermove", onPointerMove);
      window.removeEventListener("pointerdown", onPointerMove);
      window.removeEventListener("pointerup", onPointerUp);
      window.removeEventListener("pointercancel", onPointerUp);
      document.documentElement.removeEventListener("pointerleave", onPointerLeave);
      document.removeEventListener("visibilitychange", onVisibility);
      gl.deleteProgram(program.program);
      gl.deleteBuffer(buffer);
      gl.deleteVertexArray(vao);
      gl.getExtension("WEBGL_lose_context")?.loseContext();
      canvas.remove();
    };
  }, []);

  return (
    <div ref={containerRef} className={["relative h-full w-full overflow-hidden", className].filter(Boolean).join(" ")} style={style} />
  );
};

export default Aurora;
