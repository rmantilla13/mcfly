"use client";

import { cn } from "cn";
import { useEffect, useRef } from "react";
import type { Mood } from "@/lib/mood";
import {
  SKY_CREAM,
  SKY_LOOKS,
  blendStops,
  clamp,
  easeInOutSine,
  hexRgb,
  mixLab,
  skyStops,
  skyStrength,
  srgbToOklab,
  type Lab,
  type Lch,
  type Rgb,
  type SkyStyle,
} from "@/lib/sky";
import { SKY_VERTEX, skyFragment } from "./sky-shaders";

// The display's sky backdrops (display/qml/components/Backdrop.qml and
// display/shaders/<style>.frag) for the console: one of five moving skies in
// the glow colours, each a fragment shader of its own (sky-shaders.ts, the
// display's line for line), laid on a canvas by an OKLab mix so it is a
// pastel wash on the warm canvas by day and a glow over the near-black one
// at night. Without WebGL it draws nothing, so put it on something that
// already has a background. One WebGL context per mount, as MeshGradient.
//
//   <SkyBackdrop className="absolute inset-0" sky="arc" />
//   <SkyBackdrop sky={data.backdrop} dark={night} fade={90} canvas={["--ambient-canvas-day", "--ambient-canvas-night"]} />
//
// Arc: an aurora band curving across the sky, bright along its lower edge,
// rays running up through it. Ribbons: three thin curtains edge-on, folding.
// Dawn: a horizon gradient, a low sun glow, haze. Silk: two sheets of satin
// folding over each other. Pillars: columns of light standing up from the
// bottom edge. (Mesh, the backdrop's other choice, is MeshGradient.)
//
// Colour: the stops are the --glow-1..3 tokens (the mood's colours, swapped
// by data-mood on <html>) and the display's fourth, the cream of the mood
// (lib/sky.ts SKY_CREAM), in OKLCh with the hues unwrapped so blends take
// the short way round; a new palette glides in over 4 s, the display's
// moodFade. The canvas is a day colour and a night one, mixed in OKLab by
// how far into the night look it is: `dark` brings that in over `fade`
// seconds, and the style's strength (lib/sky.ts SKY_LOOKS) rises with it.
//
// Motion: the display's own pace (`speed` 1 is its seconds), at most `maxFps`
// frames a second, sleeping between them rather than skipping, and only
// while on screen and the tab is shown. The clock starts from the wall
// clock, so a remount carries on rather than replaying the same opening.
// With prefers-reduced-motion it draws one still frame, and a change of
// palette, canvas or style lands at once. Each sky runs at a fraction of
// the device's pixels (SKY_LOOKS.resolution: ribbons 0.4, the rest 0.5): a
// soft picture loses nothing scaled up.

export type SkyBackdropProps = {
  sky: SkyStyle;
  dark?: boolean; // the night look; left out, follows the theme (.dark on <html>)
  // The canvas by day and at night: CSS colours, or custom properties
  // (--…) read from this element. The display's own canvases if left out.
  canvas?: readonly [day: string, night: string];
  speed?: number; // 1: the display's pace
  resolution?: number; // canvas pixels as a fraction of devicePixelRatio; the style's own if left out
  maxFps?: number; // redraws a second (0: every frame); backdrops use 15
  fade?: number; // seconds the night look takes to come in
  brightness?: number; // scales the style's strength
  seed?: number; // a different sky
  className?: string;
};

type Settings = {
  sky: SkyStyle;
  dark?: boolean;
  canvas: readonly [string, string];
  speed: number;
  resolution?: number;
  maxFps: number;
  fade: number;
  brightness: number;
  seed: number;
};

type Program = { program: WebGLProgram; uniforms: Record<string, WebGLUniformLocation | null> };
type Gpu = { gl: WebGLRenderingContext; buffer: WebGLBuffer | null; programs: Map<SkyStyle, Program | null> };

const GLOW_TOKENS = ["--glow-1", "--glow-2", "--glow-3"];
// The display's canvases (Theme.qml: the day palette's background and the
// night palette's).
const DISPLAY_CANVAS: readonly [string, string] = ["#f1efeb", "#121317"];
const PALETTE_SECONDS = 4; // a new palette glides in over the display's moodFade
const MOODS: readonly Mood[] = ["morning", "day", "evening", "night"];

// Everything a redraw depends on, as one string: a parent that re-renders
// every second (Ambient's clock) with the same props doesn't wake the loop.
const settingsKey = (s: Settings) =>
  [s.sky, s.dark, s.canvas.join(","), s.speed, s.resolution, s.maxFps, s.fade, s.brightness, s.seed].join("|");

function compile(gl: WebGLRenderingContext, type: number, source: string) {
  const shader = gl.createShader(type);
  if (!shader) return null;
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (gl.getShaderParameter(shader, gl.COMPILE_STATUS)) return shader;
  console.error("SkyBackdrop shader:", gl.getShaderInfoLog(shader));
  gl.deleteShader(shader);
  return null;
}

function link(gl: WebGLRenderingContext, style: SkyStyle): Program | null {
  const vertex = compile(gl, gl.VERTEX_SHADER, SKY_VERTEX);
  const fragment = compile(gl, gl.FRAGMENT_SHADER, skyFragment(style));
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
    if (info) uniforms[info.name] = gl.getUniformLocation(program, info.name);
  }
  return { program, uniforms };
}

export function SkyBackdrop({
  sky,
  dark,
  canvas: canvasColors = DISPLAY_CANVAS,
  speed = 1,
  resolution,
  maxFps = 15,
  fade = 2,
  brightness = 1,
  seed = 0,
  className,
}: SkyBackdropProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const wakeRef = useRef<(() => void) | null>(null);
  const settings: Settings = {
    sky: sky in SKY_LOOKS ? sky : "arc",
    dark,
    canvas: canvasColors,
    speed: Math.max(0, speed),
    resolution: resolution === undefined ? undefined : clamp(resolution, 0.1, 2),
    maxFps: Math.max(0, maxFps),
    fade: Math.max(0, fade),
    brightness: Math.max(0, brightness),
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
    const attributes = { alpha: false, antialias: false, depth: false, stencil: false, powerPreference: "low-power" as const };
    // The shaders are GLSL ES 1.00, which either context compiles.
    const gl = (canvas.getContext("webgl2", attributes) ?? canvas.getContext("webgl", attributes)) as WebGLRenderingContext | null;
    if (!gl) return undefined;
    // What the context holds. The browser can take the context away (a GPU
    // reset, waking from sleep) and give it back empty, so this is built
    // again when it does. A style's program is linked the first time it is
    // drawn and kept, so a change of style costs one compile.
    const build = (): Gpu | null => {
      const buffer = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
      gl.enableVertexAttribArray(0);
      gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
      const programs = new Map<SkyStyle, Program | null>();
      programs.set(settingsRef.current.sky, link(gl, settingsRef.current.sky));
      return programs.get(settingsRef.current.sky) ? { gl, buffer, programs } : null;
    };
    let gpu = build();
    if (!gpu) {
      gl.getExtension("WEBGL_lose_context")?.loseContext();
      return undefined;
    }
    container.appendChild(canvas);
    const programFor = (style: SkyStyle) => {
      if (!gpu) return null;
      if (!gpu.programs.has(style)) gpu.programs.set(style, link(gl, style));
      return gpu.programs.get(style) ?? null;
    };

    // Any CSS colour, read back through a 1 px canvas; a custom property
    // (--…) is read from this element first.
    const probe = document.createElement("canvas").getContext("2d", { willReadFrequently: true });
    const parsed = new Map<string, Rgb>();
    const parse = (value: string, fallback: string): Rgb => {
      const known = parsed.get(value);
      if (known) return known;
      let rgb = hexRgb(fallback);
      if (probe) {
        probe.clearRect(0, 0, 1, 1);
        probe.fillStyle = fallback;
        probe.fillStyle = value;
        probe.fillRect(0, 0, 1, 1);
        const [r, g, b] = probe.getImageData(0, 0, 1, 1).data;
        rgb = [r / 255, g / 255, b / 255];
      }
      parsed.set(value, rgb);
      return rgb;
    };
    const resolve = (value: string, fallback: string) =>
      value.startsWith("--") ? getComputedStyle(container).getPropertyValue(value).trim() || fallback : value;

    const root = document.documentElement;
    const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
    const born = performance.now();
    // In the first second (a display zone that differs from the browser's
    // lands just after mount) or for less motion, a change is simply there:
    // a page never opens on a fade.
    const snap = (now: number) => now - born < 1000 || reduce;

    // The stops: the current palette glides to the newest one in OKLCh.
    const glide = { key: "", from: [] as Lch[], to: [] as Lch[], start: 0, mix: 1 };
    const shownStops = (now: number) => {
      if (glide.mix < 1) glide.mix = Math.min(1, (now - glide.start) / (PALETTE_SECONDS * 1000));
      return glide.mix < 1 ? blendStops(glide.from, glide.to, easeInOutSine(glide.mix)) : glide.to;
    };
    const targetStops = (now: number) => {
      const css = getComputedStyle(root);
      let glow = GLOW_TOKENS.map((name) => css.getPropertyValue(name).trim()).filter(Boolean);
      if (glow.length < 3) glow = ["#5b7cf5", "#f07f5a", "#f6b94a"];
      const mood = root.dataset.mood;
      const cream = SKY_CREAM[MOODS.includes(mood as Mood) ? (mood as Mood) : "day"];
      const key = [...glow, cream].join("|");
      if (key === glide.key) return;
      glide.key = key;
      const next = skyStops([...glow, cream].map((c, i) => parse(c, i < 3 ? ["#5b7cf5", "#f07f5a", "#f6b94a"][i] : cream)));
      if (!glide.to.length || snap(now)) {
        glide.from = next;
        glide.to = next;
        glide.mix = 1;
        return;
      }
      glide.from = shownStops(now);
      glide.to = next;
      glide.start = now;
      glide.mix = 0;
    };

    // How far into the night look: eases from where it is to the newest
    // target over `fade` seconds. The canvas and the strength follow it.
    const dusk = { from: 0, to: 0, now: 0, start: 0, ms: 0 };
    const targetDusk = (now: number) => {
      const s = settingsRef.current;
      const to = (s.dark ?? root.classList.contains("dark")) ? 1 : 0;
      if (to === dusk.to) return;
      dusk.to = to;
      if (snap(now) || s.fade === 0) {
        dusk.from = to;
        dusk.now = to;
        dusk.ms = 0;
        return;
      }
      dusk.from = dusk.now;
      dusk.start = now;
      dusk.ms = s.fade * 1000;
    };
    const easingDusk = (now: number) => dusk.ms > 0 && now - dusk.start < dusk.ms;
    const easeDusk = (now: number) => {
      if (!easingDusk(now)) dusk.now = dusk.to;
      else dusk.now = dusk.from + (dusk.to - dusk.from) * easeInOutSine((now - dusk.start) / dusk.ms);
    };
    // The two canvases, read when anything may have changed them, not a frame.
    let canvases: [Lab, Lab] = [srgbToOklab(hexRgb(DISPLAY_CANVAS[0])), srgbToOklab(hexRgb(DISPLAY_CANVAS[1]))];
    const targetCanvas = () => {
      const s = settingsRef.current;
      canvases = [
        srgbToOklab(parse(resolve(s.canvas[0], DISPLAY_CANVAS[0]), DISPLAY_CANVAS[0])),
        srgbToOklab(parse(resolve(s.canvas[1], DISPLAY_CANVAS[1]), DISPLAY_CANVAS[1])),
      ];
    };
    const target = (now: number) => {
      targetStops(now);
      targetDusk(now);
      targetCanvas();
    };
    const easing = (now: number) => glide.mix < 1 || easingDusk(now);

    const view = { width: 1, height: 1 };
    // Seconds of motion, from the wall clock within the hour (small enough
    // for the shader's 32-bit floats to step evenly), as the display's.
    let clock = ((Date.now() / 1000) % 3600) * settingsRef.current.speed + settingsRef.current.seed * 37;
    let raf = 0;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let last = 0;
    let visible = true;

    const render = (now: number) => {
      if (!gpu || gl.isContextLost()) return;
      const s = settingsRef.current;
      const program = programFor(s.sky);
      if (!program) return;
      const u = program.uniforms;
      const stops = shownStops(now);
      const lab = mixLab(canvases[0], canvases[1], dusk.now);
      gl.viewport(0, 0, canvas.width, canvas.height);
      gl.useProgram(program.program);
      gl.bindBuffer(gl.ARRAY_BUFFER, gpu.buffer);
      gl.enableVertexAttribArray(0);
      gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
      gl.uniform2f(u.size, canvas.width, canvas.height);
      gl.uniform1f(u.time, clock);
      gl.uniform1f(u.strength, skyStrength(s.sky, dusk.now, s.brightness));
      gl.uniform1f(u.seed, s.seed);
      gl.uniform1f(u.dim, 1);
      gl.uniform4f(u.canvas, lab[0], lab[1], lab[2], 0);
      gl.uniform4f(u.s0, stops[0][0], stops[0][1], stops[0][2], 0);
      gl.uniform4f(u.s1, stops[1][0], stops[1][1], stops[1][2], 0);
      gl.uniform4f(u.s2, stops[2][0], stops[2][1], stops[2][2], 0);
      gl.uniform4f(u.s3, stops[3][0], stops[3][1], stops[3][2], 0);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    };

    const stop = () => {
      cancelAnimationFrame(raf);
      clearTimeout(timer);
      raf = 0;
      timer = undefined;
    };

    // The frame after the one at `now`, `slot` ms on: a capped loop sleeps
    // on a timer until just before its slot and then takes the next
    // refresh, so a backdrop at 15 frames a second wakes about 15 times a
    // second (MeshGradient does the same).
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
      if (slot && last && now - last < slot - (slot >= 14 ? 8 : 2)) {
        raf = requestAnimationFrame(frame);
        return;
      }
      const dt = last ? clamp((now - last) / 1000, 0, 0.25) : 0;
      last = now;
      easeDusk(now);
      if (!reduce) clock += dt * s.speed;
      render(now);
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
      const ratio = Math.min((s.resolution ?? SKY_LOOKS[s.sky].resolution) * (window.devicePixelRatio || 1), 2);
      canvas.width = Math.max(1, Math.round(view.width * ratio));
      canvas.height = Math.max(1, Math.round(view.height * ratio));
      const now = performance.now();
      target(now);
      easeDusk(now);
      render(now);
      wake();
    };

    const onVisibility = () => {
      last = 0;
      wake();
    };

    // Lost: ask for the context back (preventDefault) and stop until it
    // comes. Restored: build again and carry on from where it stopped.
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
    // (.dark), both on <html>; the canvas tokens with this element's own
    // classes (Ambient's night).
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

    let lastRatio = `${settingsRef.current.resolution}|${settingsRef.current.sky}`;
    wakeRef.current = () => {
      const s = settingsRef.current;
      const ratio = `${s.resolution}|${s.sky}`;
      if (ratio !== lastRatio) {
        lastRatio = ratio;
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
        for (const program of gpu.programs.values()) if (program) gl.deleteProgram(program.program);
        gl.deleteBuffer(gpu.buffer);
      }
      gl.getExtension("WEBGL_lose_context")?.loseContext();
      canvas.remove();
    };
  }, []);

  return <div ref={containerRef} aria-hidden="true" className={cn("pointer-events-none relative h-full w-full overflow-hidden", className)} />;
}
