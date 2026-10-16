"use client";

import { cn } from "cn";
import { useEffect, useRef } from "react";
import { clamp, meshLayout, meshPalette, newMeshLayout, type Rgb, srgbToOklab, wrap } from "@/lib/mesh";

// The display's moving gradient (display/qml/components/GradientTile.qml and
// display/shaders/gradienttile.frag) for the console: four soft colour fields
// drifting over each other, optional frosted-glass rings blurred into them,
// and a static film grain, in one WebGL2 pass. Without WebGL2 it draws
// nothing, so put it on something that already has a background.
//
// Each mount is a WebGL context of its own. A browser keeps about 16 live on
// a page (fewer on phones) and drops the oldest for good past that, so it's
// for a backdrop and a handful of tiles (8 at most, counting the page's
// other WebGL users), not for every row of a list.
//
//   <MeshGradient className="absolute inset-0" />           // the glow (--glow-*)
//   <MeshGradient baseColor={event.color} rings={1} />      // a tile in one colour
//
// Colour, as on the display: the source hues (the --glow tokens, `colors`, or
// one `baseColor` and its two analogous hues) are mapped to luminous pastels
// by day and to deep, quiet tones at night (`dark`; left out, it follows the
// theme). The fields are blended in OKLab with their chroma kept, so blue into
// coral goes through violet and rose rather than grey. A new palette (another
// mood, the theme, a new colour) eases in OKLab over `fade` seconds.
//
// Motion: each centre wanders on three sines at 1, φ and e times its own rate,
// so the paths never close and the picture never repeats, unlike the
// display's seamless loop. The paths are worked out here once a frame and the
// shader only reads them. The clock starts from the wall clock, so a remount
// carries on rather than replaying the same opening. It draws at most `maxFps`
// times a second (sleeping between frames rather than skipping them), stops
// when offscreen or the tab is hidden, and draws one still frame for people
// who ask for less motion.

export type MeshGradientProps = {
  colors?: string[]; // 3-4 source colours instead of the glow tokens
  baseColor?: string; // one colour; its analogous hues make up the rest
  dark?: boolean; // the night look; left out, follows the theme (.dark on <html>)
  speed?: number; // 1: the display tile's pace, about 48 s around
  resolution?: number; // canvas pixels as a fraction of devicePixelRatio
  maxFps?: number; // redraws a second (0: every frame); backdrops use 15
  rings?: 0 | 1 | 2; // frosted-glass rings
  grain?: boolean; // static film grain, which also dithers the gradient
  intensity?: number; // 0..1: 1 is an opaque tile, less lets the page through
  fade?: number; // seconds a palette change takes
  seed?: number; // per-tile variation: layout mirror and path phases
  className?: string;
};

type Settings = Required<Omit<MeshGradientProps, "colors" | "baseColor" | "dark" | "className">> & {
  colors?: string[];
  baseColor?: string;
  dark?: boolean;
};

// The palette and the paths live in lib/mesh.ts (tested there); they are
// still exported from here for the pages that took them from this file.
export { meshLayout, meshPalette, newMeshLayout, srgbToOklab };
export type { MeshLayout } from "@/lib/mesh";

// ---- Shaders

export const MESH_VERTEX = `#version 300 es
in vec2 aPosition;
void main() {
  gl_Position = vec4(aPosition, 0.0, 1.0);
}`;

// Per pixel: 4 exp for the fields (+4 with rings), the OKLab blend and one
// conversion to sRGB, 2 hashes for the grain. Everything that depends only
// on time arrives as a uniform.
export const MESH_FRAGMENT = `#version 300 es
precision highp float;
uniform vec2 uSize;      // CSS px
uniform float uDpr;      // canvas px per CSS px
uniform vec4 uColor[4];  // OKLab L a b, and chroma: main, analogous +, analogous -, highlight
uniform vec2 uCentre[4]; // colour-field centres, CSS px
uniform float uInv;
uniform vec4 uRing1;     // centre, radius, on
uniform vec4 uRing2;
uniform float uGlass;    // rims and frost (dimmer at night)
uniform float uRim;      // rim strength
uniform float uGrain;
uniform float uIntensity;
out vec4 outColor;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float blob(vec2 p, vec2 c, float inv) {
  vec2 d = p - c;
  return exp(-dot(d, d) * inv);
}

vec3 oklabToSrgb(vec3 c) {
  float l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
  float m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
  float s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
  l = l * l * l;
  m = m * m * m;
  s = s * s * s;
  vec3 lin = clamp(vec3(
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
  ), 0.0, 1.0);
  return mix(lin * 12.92, 1.055 * pow(lin, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, lin));
}

void main() {
  vec2 p = vec2(gl_FragCoord.x, uSize.y * uDpr - gl_FragCoord.y) / uDpr;
  float px = 1.0 / uDpr;
  const vec3 white = vec3(1.0, 0.0, 0.0);

  // Glass rings first: inside one the fields are sampled magnified and
  // shifted, so it reads as a lens. Blurred into the gradient, as the
  // display's tiles are (soft = 1).
  vec2 ps = p;
  float in1 = 0.0, in2 = 0.0, l1 = 0.0, l2 = 0.0;
  vec2 d1 = vec2(0.0), d2 = vec2(0.0);
  float R1 = uRing1.z, R2 = uRing2.z;
  bool rings = uRing1.w + uRing2.w > 0.5;
  if (rings) {
    d1 = p - uRing1.xy;
    d2 = p - uRing2.xy;
    l1 = length(d1);
    l2 = length(d2);
    float ew1 = max(px, 0.07 * R1);
    float ew2 = max(px, 0.07 * R2);
    in1 = uRing1.w * (1.0 - smoothstep(R1 - ew1, R1 + ew1, l1));
    in2 = uRing2.w * (1.0 - smoothstep(R2 - ew2, R2 + ew2, l2));
    ps -= 0.65 * in1 * (0.14 * d1 + vec2(0.07, -0.05) * R1) + 0.65 * in2 * (0.14 * d2 + vec2(-0.05, 0.07) * R2);
  }

  // Three colour fields averaged in OKLab, with the chroma put back (an
  // average of two hues is greyer than either), then the highlight.
  float w0 = blob(ps, uCentre[0], uInv) + 0.02;
  float w1 = blob(ps, uCentre[1], uInv);
  float w2 = blob(ps, uCentre[2], uInv * 1.2);
  float wsum = w0 + w1 + w2;
  vec3 lab = (uColor[0].xyz * w0 + uColor[1].xyz * w1 + uColor[2].xyz * w2) / wsum;
  float chroma = (uColor[0].w * w0 + uColor[1].w * w1 + uColor[2].w * w2) / wsum;
  lab.yz *= min(chroma / max(length(lab.yz), 1e-4), 2.5);
  lab = mix(lab, uColor[3].xyz, 0.62 * blob(ps, uCentre[3], uInv * 2.4));

  // A faint sheen from the top, like light on a glass sheet.
  lab.x += uGlass * 0.03 * (1.0 - p.y / uSize.y);

  if (rings) {
    // Frost: a faint fill brightening toward the rim; the overlap tinted.
    float e1 = min(l1 / max(R1, 1.0), 1.0);
    float e2 = min(l2 / max(R2, 1.0), 1.0);
    float frost = in1 * (0.07 + 0.072 * e1 * e1 * e1) + in2 * (0.07 + 0.072 * e2 * e2 * e2);
    lab = mix(lab, uColor[2].xyz, 0.3 * in1 * in2);
    lab = mix(lab, white, uGlass * uGlass * frost);
    // Rims: a soft ridge across each edge, lit from the top left, and a halo.
    vec2 L = vec2(-0.6, -0.8);
    float g1 = abs(l1 - R1);
    float g2 = abs(l2 - R2);
    float k1 = max(0.55 + 0.5 * px, 0.03 * R1);
    float k2 = max(0.55 + 0.5 * px, 0.03 * R2);
    float rim1 = uRing1.w * exp(-g1 * g1 / (k1 * k1)) * (0.6 + 0.4 * dot(d1 / max(l1, 0.001), L));
    float rim2 = uRing2.w * exp(-g2 * g2 / (k2 * k2)) * (0.6 + 0.4 * dot(d2 / max(l2, 0.001), L));
    float h1 = max(4.0, 0.1 * R1);
    float h2 = max(4.0, 0.1 * R2);
    float halo = uRing1.w * exp(-g1 * g1 / (h1 * h1)) + uRing2.w * exp(-g2 * g2 / (h2 * h2));
    float lines = 0.5 * (rim1 + rim2) + 0.16 * halo;
    lab = mix(lab, white, uGlass * uRim * clamp(lines, 0.0, 1.0));
  }

  // Film grain: static, one value per canvas pixel, triangular (two hashes)
  // so it clusters around zero like real grain. It also dithers the ramps.
  vec3 col = oklabToSrgb(lab);
  vec2 gp = floor(gl_FragCoord.xy);
  col += (hash12(gp) + hash12(gp.yx * 1.618 + 71.3) - 1.0) * uGrain;
  outColor = vec4(clamp(col, 0.0, 1.0) * uIntensity, uIntensity);
}`;

// ---- The component

type Program = { program: WebGLProgram; uniforms: Record<string, WebGLUniformLocation | null> };

function link(gl: WebGL2RenderingContext): Program | null {
  const compile = (type: number, source: string) => {
    const shader = gl.createShader(type);
    if (!shader) return null;
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (gl.getShaderParameter(shader, gl.COMPILE_STATUS)) return shader;
    gl.deleteShader(shader);
    return null;
  };
  const vertex = compile(gl.VERTEX_SHADER, MESH_VERTEX);
  const fragment = compile(gl.FRAGMENT_SHADER, MESH_FRAGMENT);
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
}

const GLOW_TOKENS = ["--glow-1", "--glow-2", "--glow-3"];
const PALETTE = 13; // 4 OKLab colours, then the night factor

// Everything a redraw depends on, as one string: a parent that re-renders
// every second (Ambient's clock) with the same props doesn't wake the loop.
const settingsKey = (s: Settings) =>
  [s.colors?.join(","), s.baseColor, s.dark, s.speed, s.resolution, s.maxFps, s.rings, s.grain, s.intensity, s.fade, s.seed].join("|");

type Gpu = Program & { buffer: WebGLBuffer | null; vao: WebGLVertexArrayObject | null };

export function MeshGradient({
  colors,
  baseColor,
  dark,
  speed = 1,
  resolution = 1,
  maxFps = 30,
  rings = 0,
  grain = true,
  intensity = 1,
  fade = 2,
  seed = 0,
  className,
}: MeshGradientProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const wakeRef = useRef<(() => void) | null>(null);
  const settings: Settings = {
    colors,
    baseColor,
    dark,
    speed: Math.max(0, speed),
    resolution: clamp(resolution, 0.1, 2),
    maxFps: Math.max(0, maxFps),
    rings,
    grain,
    intensity: clamp(intensity, 0, 1),
    fade: Math.max(0, fade),
    seed,
  };
  const settingsRef = useRef(settings);

  // New props reach the running loop here (not during render), and wake it
  // only if something changed.
  useEffect(() => {
    const changed = settingsKey(settings) !== settingsKey(settingsRef.current);
    settingsRef.current = settings;
    if (changed) wakeRef.current?.();
  });

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return undefined;
    // A canvas of its own per mount: the cleanup loses its context, and a
    // remount (React runs effects twice in development) must not reuse it.
    const canvas = document.createElement("canvas");
    canvas.className = "absolute inset-0 block h-full w-full";
    const gl = canvas.getContext("webgl2", { alpha: true, premultipliedAlpha: true, antialias: false, depth: false, stencil: false });
    if (!gl) return undefined;
    // What the context holds. The browser can take the context away (a GPU
    // reset, waking from sleep) and give it back empty, so this is built
    // again when it does.
    const build = (): Gpu | null => {
      const program = link(gl);
      if (!program) return null;
      const buffer = gl.createBuffer();
      const vao = gl.createVertexArray();
      gl.bindVertexArray(vao);
      gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
      gl.enableVertexAttribArray(0);
      gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
      return { ...program, buffer, vao };
    };
    let gpu = build();
    if (!gpu) {
      gl.getExtension("WEBGL_lose_context")?.loseContext();
      return undefined;
    }
    container.appendChild(canvas);

    // Any CSS colour, read back through a 1 px canvas.
    const probe = document.createElement("canvas").getContext("2d", { willReadFrequently: true });
    const parsed = new Map<string, Rgb>();
    const parse = (value: string): Rgb => {
      const known = parsed.get(value);
      if (known) return known;
      let rgb: Rgb = [0.36, 0.49, 0.96];
      if (probe) {
        probe.clearRect(0, 0, 1, 1);
        probe.fillStyle = "#5b7cf5";
        probe.fillStyle = value;
        probe.fillRect(0, 0, 1, 1);
        const [r, g, b] = probe.getImageData(0, 0, 1, 1).data;
        rgb = [r / 255, g / 255, b / 255];
      }
      parsed.set(value, rgb);
      return rgb;
    };

    const root = document.documentElement;
    const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;

    // The palette eases from where it is to the newest target, in OKLab,
    // over `fade` seconds; the night factor (glass, grain, pace) with it.
    const palette = { from: new Float32Array(PALETTE), to: new Float32Array(PALETTE), now: new Float32Array(PALETTE), start: 0, ms: 0, key: "" };
    const born = performance.now();
    const target = (now: number) => {
      const s = settingsRef.current;
      const night = s.dark ?? root.classList.contains("dark");
      let source: string[];
      if (s.colors && s.colors.length >= 3) source = s.colors;
      else if (s.baseColor) source = [s.baseColor];
      else {
        const css = getComputedStyle(root);
        source = GLOW_TOKENS.map((name) => css.getPropertyValue(name).trim()).filter(Boolean);
        if (source.length < 3) source = ["#5b7cf5", "#f07f5a", "#f6b94a"];
      }
      const rgb = source.map(parse);
      const key = `${night}|${rgb.join(";")}`;
      if (key === palette.key) return;
      palette.key = key;
      meshPalette(rgb, night).forEach((lab, i) => palette.to.set(lab, i * 3));
      palette.to[12] = night ? 1 : 0;
      // In the first second (a display zone that differs from the browser's
      // lands just after mount) or for less motion, the new palette is
      // simply there: a page never opens on a fade. A change while hidden
      // still eases on the clock, so a tab that comes back lands where the
      // page's CSS is.
      if (now - born < 1000 || reduce || s.fade === 0) {
        palette.from.set(palette.to);
        palette.now.set(palette.to);
        palette.ms = 0;
        return;
      }
      palette.from.set(palette.now);
      palette.start = now;
      palette.ms = s.fade * 1000;
    };
    const easing = (now: number) => palette.ms > 0 && now - palette.start < palette.ms;
    const ease = (now: number) => {
      if (!easing(now)) {
        palette.now.set(palette.to);
        return;
      }
      const x = clamp((now - palette.start) / palette.ms, 0, 1);
      const k = x * x * (3 - 2 * x);
      for (let i = 0; i < PALETTE; i++) palette.now[i] = palette.from[i] + (palette.to[i] - palette.from[i]) * k;
    };

    const colours = new Float32Array(16);
    const layout = newMeshLayout();
    const view = { width: 1, height: 1 };
    // Seconds of motion, from the wall clock: a remount picks up the drift
    // where it would be, not from the same opening every time.
    let clock = (Date.now() / 1000) * settingsRef.current.speed;
    let raf = 0;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let last = 0;
    let visible = true;

    const render = () => {
      if (!gpu || gl.isContextLost()) return;
      const s = settingsRef.current;
      const u = gpu.uniforms;
      const p = palette.now;
      const night = p[12];
      for (let i = 0; i < 4; i++) {
        const a = p[i * 3 + 1];
        const b = p[i * 3 + 2];
        colours[i * 4] = p[i * 3];
        colours[i * 4 + 1] = a;
        colours[i * 4 + 2] = b;
        colours[i * 4 + 3] = Math.hypot(a, b);
      }
      const period = 48 * (0.85 + 0.3 * wrap(s.seed * 0.618034 + 0.3));
      meshLayout((clock * 2 * Math.PI) / period + s.seed * 1.7, view.width, view.height, s.seed, s.rings, layout);
      gl.viewport(0, 0, canvas.width, canvas.height);
      gl.useProgram(gpu.program);
      gl.bindVertexArray(gpu.vao);
      gl.uniform2f(u.uSize, view.width, view.height);
      gl.uniform1f(u.uDpr, canvas.width / view.width);
      gl.uniform4fv(u.uColor, colours);
      gl.uniform2fv(u.uCentre, layout.centres);
      gl.uniform1f(u.uInv, layout.inv);
      gl.uniform4fv(u.uRing1, layout.ring1);
      gl.uniform4fv(u.uRing2, layout.ring2);
      gl.uniform1f(u.uGlass, 1 - 0.65 * night);
      gl.uniform1f(u.uRim, 0.8 - 0.35 * night);
      gl.uniform1f(u.uGrain, s.grain ? 0.035 * (1 - 0.3 * night) : 0);
      gl.uniform1f(u.uIntensity, s.intensity);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    };

    const stop = () => {
      cancelAnimationFrame(raf);
      clearTimeout(timer);
      raf = 0;
      timer = undefined;
    };

    // The frame after the one at `now`, `slot` ms on. A capped loop sleeps on
    // a timer until just before its slot (counted from the frame's own time,
    // so a late start doesn't push it a refresh later) and then takes the
    // next refresh: a backdrop at 15 frames a second wakes about 15 times a
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
      if (!visible || document.hidden || !gpu) return;
      const s = settingsRef.current;
      const slot = s.maxFps > 0 ? 1000 / s.maxFps : 0;
      // Early for its slot: by more than half a refresh after the timer (a
      // frame asked for mid-refresh can carry that refresh's earlier time),
      // or at all for a cap near the refresh rate, which has no timer and
      // skips refreshes instead.
      if (slot && last && now - last < slot - (slot >= 14 ? 8 : 2)) {
        raf = requestAnimationFrame(frame);
        return;
      }
      const dt = last ? clamp((now - last) / 1000, 0, 0.25) : 0;
      last = now;
      ease(now);
      // The night drifts a little slower, as on the display.
      if (!reduce) clock += dt * s.speed * (1 - 0.35 * palette.now[12]);
      render();
      if ((!reduce && s.speed > 0) || easing(now)) next(slot, now);
      else last = 0;
    };

    const wake = () => {
      target(performance.now());
      if (!raf && !timer && gpu && visible && !document.hidden) raf = requestAnimationFrame(frame);
    };

    const resize = () => {
      const s = settingsRef.current;
      view.width = Math.max(1, container.clientWidth);
      view.height = Math.max(1, container.clientHeight);
      const ratio = Math.min(s.resolution * (window.devicePixelRatio || 1), 2);
      canvas.width = Math.max(1, Math.round(view.width * ratio));
      canvas.height = Math.max(1, Math.round(view.height * ratio));
      target(performance.now());
      ease(performance.now());
      render();
      wake();
    };

    const onVisibility = () => {
      last = 0;
      wake();
    };

    // Lost: ask for the context back (preventDefault) and stop until it
    // comes. Restored: build again and carry on from where it stopped.
    // One dropped for too many on the page never comes back, even after
    // others close (Chrome 155), and the tile shows what's behind it: hence
    // the budget at the top.
    const onLost = (event: Event) => {
      event.preventDefault();
      stop();
      last = 0;
      gpu = null;
    };
    const onRestored = () => {
      gpu = build();
      resize();
    };
    canvas.addEventListener("webglcontextlost", onLost);
    canvas.addEventListener("webglcontextrestored", onRestored);

    // The glow tokens change with the mood (data-mood) and the theme
    // (.dark), both on <html>.
    const mutations = new MutationObserver(wake);
    mutations.observe(root, { attributes: true, attributeFilter: ["class", "style", "data-mood"] });
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
    document.addEventListener("visibilitychange", onVisibility);
    resize();

    let lastResolution = settingsRef.current.resolution;
    wakeRef.current = () => {
      if (settingsRef.current.resolution !== lastResolution) {
        lastResolution = settingsRef.current.resolution;
        resize();
        return;
      }
      wake();
    };

    return () => {
      stop();
      wakeRef.current = null;
      // Off first, so losing the context here doesn't ask for it back.
      canvas.removeEventListener("webglcontextlost", onLost);
      canvas.removeEventListener("webglcontextrestored", onRestored);
      mutations.disconnect();
      resizeObserver.disconnect();
      intersection.disconnect();
      document.removeEventListener("visibilitychange", onVisibility);
      if (gpu) {
        gl.deleteProgram(gpu.program);
        gl.deleteBuffer(gpu.buffer);
        gl.deleteVertexArray(gpu.vao);
      }
      gl.getExtension("WEBGL_lose_context")?.loseContext();
      canvas.remove();
    };
  }, []);

  return <div ref={containerRef} aria-hidden="true" className={cn("pointer-events-none relative h-full w-full overflow-hidden", className)} />;
}
