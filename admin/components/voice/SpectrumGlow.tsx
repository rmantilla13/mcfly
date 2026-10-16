"use client";

import { useEffect, useRef } from "react";

// The voice glow from the Homestead app, as on the display
// (display/shaders/spectrumglow.frag, ported to WebGL): seven soft colour
// lobes rise from the bottom with the voice and drift sideways, a layered
// band of light bends up into a dome in front of them, and a thin spectrum
// line runs along the bottom edge. While a reply is prepared everything
// gathers into one beam that travels side to side. Additive over a dark
// page. Decorative: pair it with a text status.
//
// Everything about a lobe (where it is, how tall, its colour) depends only
// on time and the voice, so it is worked out here once a frame and the
// shader just reads it. The lobes drift at slightly different paces and
// breathe at their own rates; colours are mixed in OKLab, so green into
// amber stays clear instead of going olive; bright overlaps roll off softly
// instead of clipping. With nothing to show it redraws 20 times a second
// instead of every frame. With less motion asked for, the lobes hold still
// and keep a steady height while it listens or speaks.

export type GlowInput = {
  level: number; // the microphone, 0..1
  low: number;
  mid: number;
  high: number;
  processing: boolean;
  speaking: boolean;
};

const LOBES = 7;

const VERT = `attribute vec2 a; void main() { gl_Position = vec4(a, 0.0, 1.0); }`;

const FRAG = `precision highp float;
uniform vec2 size; uniform float radius; uniform float dpr;
uniform float energy; uniform float process; uniform float beamX; uniform float intensity;
uniform vec4 lobe[${LOBES}];  // x, height, width (Gaussian sigma), alpha; CSS px
uniform vec4 tint[${LOBES}];  // colour (sRGB), and its weight in the band's colour

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

void main() {
  vec2 p = vec2(gl_FragCoord.x, size.y * dpr - gl_FragCoord.y) / dpr;
  float w = size.x; float h = size.y; float px = 1.0 / dpr;
  float r = min(radius, min(w, h) * 0.5);
  vec2 hs = 0.5 * size;
  vec2 q = abs(p - hs) - (hs - vec2(r));
  float dBox = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
  float cover = clamp(0.5 - dBox / px, 0.0, 1.0);
  if (cover <= 0.0) { gl_FragColor = vec4(0.0); return; }

  float u = w;
  float restBend = 0.012; float bend = 0.115; float spread = 0.5; float blur = u * 0.04;
  float bandWidth = u * 0.04; float bandBlur = u * 0.016;
  float centerX = 0.5 * w + (beamX - 0.5 * w) * process;
  float halfWidth = w * (spread + (0.17 - spread) * process);
  float dx = p.x < r ? r - p.x : (p.x > w - r ? p.x - (w - r) : 0.0);
  float floorY = h - r + sqrt(max(r * r - dx * dx, 0.0));
  float bd = (p.x - centerX) / (halfWidth * 0.47);
  float bell = 1.0 / (1.0 + bd * bd);

  vec3 col = vec3(0.0); vec3 lobeSum = vec3(0.0); float lobeTotal = 1e-6;
  for (int i = 0; i < ${LOBES}; i++) {
    vec4 L = lobe[i];
    vec4 T = tint[i];
    float hx = p.x - L.x;
    float horiz = exp(-hx * hx / (2.0 * L.z * L.z));
    float top = h - L.y;
    // Rises smoothly to full at 72% of the height, then eases to half at the
    // floor: no crease where the two meet.
    float t = clamp((p.y - top) / max(L.y, 1.0), 0.0, 1.0);
    float vert = smoothstep(0.0, 0.72, t) * (1.0 - 0.5 * smoothstep(0.72, 1.0, t));
    float topSoft = smoothstep(top - blur, top + blur, p.y);
    col += T.rgb * (L.w * horiz * vert * topSoft);
    float cd = hx / (w * 0.16);
    float cw = exp(-cd * cd) * T.w + 1e-6;
    lobeSum += T.rgb * cw; lobeTotal += cw;
  }
  vec3 lobeColor = lobeSum / lobeTotal;

  float crest = u * (restBend + bend * energy) * (1.0 - process) + u * bend * 0.85 * process;
  float yc = floorY - 0.5 * bandWidth - crest * bell;
  float strength = 0.4 + 0.6 * energy;
  float dome = smoothstep(yc - bandBlur, yc + bandBlur, p.y);
  col += mix(lobeColor, vec3(1.0), 0.45) * (0.42 * strength * (0.3 + 0.7 * bell) * dome);
  float midLine = 1.0 - smoothstep(0.5 * bandWidth - bandBlur, 0.5 * bandWidth + bandBlur, abs(p.y - (yc + 0.5 * bandWidth)));
  col += mix(lobeColor, vec3(1.0), 0.30) * (0.30 * strength * (0.1 + 0.9 * bell) * midLine);
  float coreLine = 1.0 - smoothstep(0.3 * bandWidth - bandBlur, 0.3 * bandWidth + bandBlur, abs(p.y - yc));
  col += mix(lobeColor, vec3(1.0), 0.65) * (0.45 * strength * (0.4 + 0.6 * bell) * coreLine);
  float aboveLine = 1.0 - smoothstep(0.5 * bandWidth - bandBlur, 0.5 * bandWidth + bandBlur, abs(p.y - (yc - 0.6 * bandWidth)));
  col += mix(lobeColor, vec3(1.0), 0.20) * (0.30 * strength * (0.25 + 0.75 * bell) * aboveLine);

  float lineAlpha = (0.25 + 0.45 * energy) * (0.35 + 0.65 * sin(p.x / w * 3.14159265));
  float edgeD = abs(p.y - (floorY - 1.0));
  float glowLine = exp(-edgeD * edgeD / 12.5);
  float crisp = 1.0 - smoothstep(0.8 - px, 0.8 + px, edgeD);
  col += mix(lobeColor, vec3(1.0), 0.2) * (lineAlpha * (0.6 * glowLine + crisp));

  // A soft knee instead of a clamp: overlaps roll off toward white rather
  // than flattening per channel. Triangular dither where there is light, so
  // the long ramps out of black don't band.
  col = 1.0 - exp(-col * intensity * 1.25);
  vec2 f = gl_FragCoord.xy;
  col += (hash12(f) + hash12(f + 19.19) - 1.0) / 255.0 * step(1.0 / 255.0, max(col.r, max(col.g, col.b)));
  gl_FragColor = vec4(clamp(col, 0.0, 1.0) * cover, 1.0);
}`;

// ---- Colour: the display's seven stops, mixed in OKLab.

type Vec3 = [number, number, number];

const STOPS: Vec3[] = [
  [0.86, 0.28, 0.7],
  [0.56, 0.34, 0.9],
  [0.26, 0.5, 0.96],
  [0.14, 0.76, 0.76],
  [0.3, 0.76, 0.4],
  [0.96, 0.66, 0.24],
  [0.96, 0.38, 0.38],
];

function toOklab([r, g, b]: Vec3): Vec3 {
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

const encode = (c: number) => {
  const x = Math.min(1, Math.max(0, c));
  return x <= 0.0031308 ? x * 12.92 : 1.055 * Math.pow(x, 1 / 2.4) - 0.055;
};

const LAB = STOPS.map(toOklab);

// The stops' colour at `position` (they wrap), mixed in OKLab and written as
// sRGB into out[at..at+2]: the loop calls it seven times a frame and
// allocates nothing.
function paletteInto(position: number, out: Float32Array, at: number) {
  const p = ((position % LOBES) + LOBES) % LOBES;
  const i = Math.floor(p);
  const f = p - i;
  const a = LAB[i];
  const b = LAB[(i + 1) % LOBES];
  const L = a[0] + (b[0] - a[0]) * f;
  const A = a[1] + (b[1] - a[1]) * f;
  const B = a[2] + (b[2] - a[2]) * f;
  const l = (L + 0.3963377774 * A + 0.2158037573 * B) ** 3;
  const m = (L - 0.1055613458 * A - 0.0638541728 * B) ** 3;
  const s = (L - 0.0894841775 * A - 1.291485548 * B) ** 3;
  out[at] = encode(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s);
  out[at + 1] = encode(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s);
  out[at + 2] = encode(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s);
}

// Which band drives each lobe.
const BAND: ("low" | "mid" | "high")[] = ["low", "mid", "high", "mid", "low", "high", "mid"];

function compile(gl: WebGLRenderingContext, type: number, src: string) {
  const s = gl.createShader(type)!;
  gl.shaderSource(s, src);
  gl.compileShader(s);
  if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s) ?? "shader");
  return s;
}

export function SpectrumGlow({
  input,
  radius = 0,
  intensity = 1,
  className,
}: {
  input: React.RefObject<GlowInput>;
  radius?: number;
  intensity?: number;
  className?: string;
}) {
  const box = useRef<HTMLDivElement>(null);
  // Read by the running loop, so a change neither rebuilds the program nor
  // restarts the motion.
  const look = useRef({ radius, intensity });
  useEffect(() => {
    look.current = { radius, intensity };
  });

  useEffect(() => {
    const host = box.current;
    if (!host) return;
    // A canvas of its own per mount: the cleanup loses its context, and a
    // remount (React runs effects twice in development) must not reuse it.
    const el = document.createElement("canvas");
    el.style.cssText = "display:block;width:100%;height:100%";
    const gl = el.getContext("webgl", { premultipliedAlpha: false, antialias: false, depth: false, stencil: false });
    const fail = (err: unknown) => {
      console.warn("voice glow shader unavailable:", err);
      host.dataset.fallback = "1";
    };
    if (!gl) {
      fail("no WebGL");
      return;
    }

    // What the context holds. The browser can take the context away (a GPU
    // reset, waking from sleep) and give it back empty, so this is built
    // again when it does.
    const build = () => {
      const program = gl.createProgram()!;
      try {
        const vs = compile(gl, gl.VERTEX_SHADER, VERT);
        const fs = compile(gl, gl.FRAGMENT_SHADER, FRAG);
        gl.attachShader(program, vs);
        gl.attachShader(program, fs);
        gl.linkProgram(program);
        gl.deleteShader(vs);
        gl.deleteShader(fs);
        if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error("link");
      } catch (err) {
        gl.deleteProgram(program);
        throw err;
      }
      gl.useProgram(program);
      const buf = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, buf);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
      const a = gl.getAttribLocation(program, "a");
      gl.enableVertexAttribArray(a);
      gl.vertexAttribPointer(a, 2, gl.FLOAT, false, 0, 0);
      const loc = (n: string) => gl.getUniformLocation(program, n);
      const U = {
        size: loc("size"), radius: loc("radius"), dpr: loc("dpr"), energy: loc("energy"), process: loc("process"),
        beamX: loc("beamX"), intensity: loc("intensity"), lobe: loc("lobe"), tint: loc("tint"),
      };
      return { program, buf, U };
    };
    let gpu: ReturnType<typeof build> | null;
    try {
      gpu = build();
    } catch (err) {
      fail(err);
      gl.getExtension("WEBGL_lose_context")?.loseContext();
      return;
    }
    host.appendChild(el);
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const motion = reduce ? 0 : 1;

    // The canvas follows its box; nothing is measured per frame.
    const view = { w: 1, h: 1, dpr: 1 };
    const resize = () => {
      view.dpr = Math.min(window.devicePixelRatio || 1, 2);
      view.w = Math.max(1, host.clientWidth);
      view.h = Math.max(1, host.clientHeight);
      el.width = Math.round(view.w * view.dpr);
      el.height = Math.round(view.h * view.dpr);
    };
    resize();
    const sizes = new ResizeObserver(resize);
    sizes.observe(host);

    // Smoothed state, as the display's: fast attack, slower release, eased
    // beam, and the same share of the gap closed per second at any frame rate.
    const st = { time: 0, level: 0, low: 0, mid: 0, high: 0, process: 0 };
    const follow = (cur: number, target: number, dt: number, release: number) =>
      cur + (target - cur) * (1 - Math.exp(-(target > cur ? (reduce ? release : 14) : release) * dt));
    // The browser's voice has no meter, so syllables stand in for it: a new
    // loudness every 120-300 ms, now and then a short gap.
    const syllable = { level: 0, high: 0, until: 0 };
    const lobes = new Float32Array(LOBES * 4);
    const tints = new Float32Array(LOBES * 4);
    let last = performance.now();
    let frame = 0;
    let timer: ReturnType<typeof setTimeout> | undefined;

    const stop = () => {
      cancelAnimationFrame(frame);
      clearTimeout(timer);
      frame = 0;
      timer = undefined;
    };

    // The next frame: at the next refresh, or about 50 ms on when there is
    // nothing to show, sleeping on a timer in between rather than waking at
    // every refresh to skip it.
    const next = (slow: boolean) => {
      if (slow) {
        timer = setTimeout(() => {
          timer = undefined;
          frame = requestAnimationFrame(draw);
        }, 40);
      } else frame = requestAnimationFrame(draw);
    };

    const draw = (now: number) => {
      frame = 0;
      if (!gpu) return;
      const inp = input.current;
      let level = inp?.level ?? 0;
      let low = inp?.low ?? level;
      let mid = inp?.mid ?? level;
      let high = inp?.high ?? level;
      // Nothing heard, said or prepared (or nothing moving, for less
      // motion): 20 frames a second is plenty.
      const idle =
        !inp?.processing &&
        !inp?.speaking &&
        st.process < 0.01 &&
        Math.max(level, low, mid, high, st.level, st.low, st.mid, st.high) < 0.02;
      const dt = Math.min((now - last) / 1000, 0.1);
      last = now;
      st.time += dt;
      const t = st.time;

      if (inp?.speaking) {
        if (t >= syllable.until) {
          const gap = syllable.level > 0.3 && Math.random() < 0.28;
          syllable.level = gap ? syllable.level * 0.35 : 0.45 + 0.4 * Math.random();
          syllable.high = 0.65 + 0.35 * Math.random();
          syllable.until = t + (gap ? 0.08 + 0.12 * Math.random() : 0.12 + 0.18 * Math.random());
        }
        level = syllable.level;
        low = level * (0.9 + 0.1 * Math.sin(t * 2.3));
        mid = level;
        high = level * syllable.high;
      }
      if (reduce) {
        // Less motion: a steady height while there is a voice, none without.
        const on = inp?.speaking || Math.max(level, low, mid, high) > 0.02 ? 0.35 : 0;
        level = low = mid = high = on;
      }
      const release = reduce ? 1.5 : inp?.speaking ? 6 : 3.2;
      st.level = follow(st.level, level, dt, release);
      st.low = follow(st.low, low, dt, release);
      st.mid = follow(st.mid, mid, dt, release);
      st.high = follow(st.high, high, dt, release);
      st.process += ((inp?.processing ? 1 : 0) - st.process) * (1 - Math.exp(-2.6 * dt));

      // The lobes, from the voice and the clock.
      const { w, h } = view;
      const u = w;
      const process = st.process;
      const beamX = w * (0.5 + 0.3 * (0.72 * Math.sin(t * 1.3) + 0.28 * Math.sin(t * 2.11 + 1.0)) * motion);
      const centerX = 0.5 * w + (beamX - 0.5 * w) * process;
      const halfWidth = w * (0.5 + (0.17 - 0.5) * process);
      const drift = t * 0.045 * motion;
      for (let i = 0; i < LOBES; i++) {
        // Each drifts at its own slightly wavering pace, so the spacing breathes.
        const pace = i / LOBES + (t * 0.05 + 0.035 * Math.sin(t * (0.23 + 0.071 * i) + 1.7 * i)) * motion;
        const flow = pace - Math.floor(pace);
        const s = (flow * 2 - 1) * 1.2;
        const restX = 0.5 * w + s * 0.5 * w;
        const edgeFade = Math.min(1, Math.max(0, (1.2 - Math.abs(s)) / 0.35));
        const band = st[BAND[i]];
        const breath = 0.025 * Math.sin(t * 0.9 * (0.8 + 0.061 * i) + i * 2.1) * motion;
        const rd = (restX - centerX) / (halfWidth * 0.47);
        const restBell = 1 / (1 + rd * rd);
        const voiceHeight = u * (0.1 + breath + 0.56 * band) * (0.55 + 0.45 * restBell);
        const width = u * 0.24 * (1 - 0.3 * process);
        const o = i * 4;
        lobes[o] = restX + (beamX + (i - 3) * w * 0.03 - restX) * process;
        lobes[o + 1] = voiceHeight + (u * 0.56 * 0.8 - voiceHeight) * process;
        lobes[o + 2] = Math.max(1, 0.42 * width);
        lobes[o + 3] =
          (0.16 + 0.55 * Math.max(band, st.level * 0.6)) * edgeFade * (0.3 + 0.7 * restBell) * (1 - process) + 0.45 * process;
        paletteInto(i + drift, tints, o);
        tints[o + 3] = edgeFade + (1 - edgeFade) * process;
      }

      const { radius: rad, intensity: strength } = look.current;
      const U = gpu.U;
      gl.viewport(0, 0, el.width, el.height);
      gl.uniform2f(U.size, w, h);
      gl.uniform1f(U.radius, rad);
      gl.uniform1f(U.dpr, view.dpr);
      gl.uniform1f(U.energy, Math.max(st.level, 0.7 * process));
      gl.uniform1f(U.process, process);
      gl.uniform1f(U.beamX, beamX);
      gl.uniform1f(U.intensity, strength);
      gl.uniform4fv(U.lobe, lobes);
      gl.uniform4fv(U.tint, tints);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      next(idle || reduce);
    };

    // Lost: ask for the context back (preventDefault) and stop until it
    // comes. Restored: build again and carry on.
    const onLost = (event: Event) => {
      event.preventDefault();
      stop();
      gpu = null;
    };
    const onRestored = () => {
      try {
        gpu = build();
      } catch (err) {
        fail(err);
        return;
      }
      last = performance.now();
      next(false);
    };
    el.addEventListener("webglcontextlost", onLost);
    el.addEventListener("webglcontextrestored", onRestored);

    frame = requestAnimationFrame(draw);
    return () => {
      stop();
      // Off first, so losing the context here doesn't ask for it back.
      el.removeEventListener("webglcontextlost", onLost);
      el.removeEventListener("webglcontextrestored", onRestored);
      sizes.disconnect();
      if (gpu) {
        gl.deleteProgram(gpu.program);
        gl.deleteBuffer(gpu.buf);
      }
      gl.getExtension("WEBGL_lose_context")?.loseContext();
      el.remove();
    };
  }, [input]);

  return (
    <div
      ref={box}
      aria-hidden="true"
      className={className}
      // Additive over the dark page, as on the display.
      style={{ mixBlendMode: "screen" }}
    />
  );
}
