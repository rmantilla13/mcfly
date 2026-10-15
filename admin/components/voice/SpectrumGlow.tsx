"use client";

import { useEffect, useRef } from "react";

// The voice glow from the Homestead app, as on the display
// (display/shaders/spectrumglow.frag, ported to WebGL): seven soft colour
// lobes rise from the bottom with the voice and drift sideways, a layered
// band of light bends up into a dome in front of them, and a thin spectrum
// line runs along the bottom edge. While a reply is prepared everything
// gathers into one beam that travels side to side. Additive over a dark
// page. Decorative: pair it with a text status.

export type GlowInput = {
  level: number; // the microphone, 0..1
  low: number;
  mid: number;
  high: number;
  processing: boolean;
  speaking: boolean;
};

const VERT = `attribute vec2 a; void main() { gl_Position = vec4(a, 0.0, 1.0); }`;

const FRAG = `precision highp float;
uniform vec2 size; uniform float radius; uniform float dpr; uniform float time;
uniform float level; uniform float low; uniform float mid; uniform float high;
uniform float processing; uniform float motion; uniform float intensity;

vec3 palette(float position) {
  float p = mod(position, 7.0);
  float f = fract(p);
  vec3 c0 = vec3(0.86, 0.28, 0.70); vec3 c1 = vec3(0.56, 0.34, 0.90); vec3 c2 = vec3(0.26, 0.50, 0.96);
  vec3 c3 = vec3(0.14, 0.76, 0.76); vec3 c4 = vec3(0.30, 0.76, 0.40); vec3 c5 = vec3(0.96, 0.66, 0.24);
  vec3 c6 = vec3(0.96, 0.38, 0.38);
  if (p < 1.0) return mix(c0, c1, f);
  if (p < 2.0) return mix(c1, c2, f);
  if (p < 3.0) return mix(c2, c3, f);
  if (p < 4.0) return mix(c3, c4, f);
  if (p < 5.0) return mix(c4, c5, f);
  if (p < 6.0) return mix(c5, c6, f);
  return mix(c6, c0, f);
}

float bandOf(int i) {
  if (i == 0 || i == 4) return low;
  if (i == 2 || i == 5) return high;
  return mid;
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
  float restReach = 0.10; float reach = 0.56; float restBend = 0.012; float bend = 0.115;
  float spread = 0.5; float lobeWidth = 0.24; float lobeBlur = 0.04;
  float bandWidth = u * 0.04; float bandBlur = u * 0.016;

  float drift = time * 0.045 * motion;
  float process = processing;
  float beamX = w * (0.5 + 0.3 * sin(time * 1.3) * motion);
  float energy = max(level, 0.7 * process);
  float centerX = 0.5 * w + (beamX - 0.5 * w) * process;
  float halfWidth = w * (spread + (0.17 - spread) * process);
  float dx = p.x < r ? r - p.x : (p.x > w - r ? p.x - (w - r) : 0.0);
  float floorY = h - r + sqrt(max(r * r - dx * dx, 0.0));
  float bd = (p.x - centerX) / (halfWidth * 0.47);
  float bell = 1.0 / (1.0 + bd * bd);

  vec3 col = vec3(0.0); vec3 lobeSum = vec3(0.0); float lobeTotal = 1e-6;
  for (int i = 0; i < 7; i++) {
    float fi = float(i);
    float flow = fract(fi / 7.0 + time * 0.05 * motion);
    float s = (flow * 2.0 - 1.0) * 1.2;
    float restX = 0.5 * w + s * 0.5 * w;
    float edgeFade = clamp((1.2 - abs(s)) / 0.35, 0.0, 1.0);
    float band = bandOf(i);
    float breath = 0.025 * sin(time * 0.9 + fi * 2.1) * motion;
    float rd = (restX - centerX) / (halfWidth * 0.47);
    float restBell = 1.0 / (1.0 + rd * rd);
    float voiceHeight = u * (restReach + breath + reach * band) * (0.55 + 0.45 * restBell);
    float x = restX + (beamX + (fi - 3.0) * w * 0.03 - restX) * process;
    float height = voiceHeight + (u * reach * 0.8 - voiceHeight) * process;
    float width = u * lobeWidth * (1.0 - 0.3 * process);
    float alpha = ((0.16 + 0.55 * max(band, level * 0.6)) * edgeFade * (0.3 + 0.7 * restBell)) * (1.0 - process) + 0.45 * process;
    float weight = edgeFade + (1.0 - edgeFade) * process;
    vec3 color = palette(fi + drift);
    float blur = u * lobeBlur;
    float hx = abs(p.x - x);
    float horiz = 1.0 - smoothstep(0.5 * width - blur, 0.5 * width + blur, hx);
    float top = h - height;
    float t = clamp((p.y - top) / max(height, 1.0), 0.0, 1.0);
    float vert = t < 0.72 ? t / 0.72 : mix(1.0, 0.5, (t - 0.72) / 0.28);
    float topSoft = smoothstep(top - blur, top + blur, p.y);
    col += color * (alpha * horiz * vert * topSoft);
    float cd = (p.x - x) / (w * 0.16);
    float cw = exp(-cd * cd) * weight + 1e-6;
    lobeSum += color * cw; lobeTotal += cw;
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
  vec3 outc = clamp(col * intensity, 0.0, 1.2) * cover;
  gl_FragColor = vec4(outc, 1.0);
}`;

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
  const canvas = useRef<HTMLCanvasElement>(null);
  const failed = useRef(false);

  useEffect(() => {
    const el = canvas.current;
    if (!el) return;
    const gl = el.getContext("webgl", { premultipliedAlpha: false, antialias: false });
    if (!gl) {
      failed.current = true;
      el.dataset.fallback = "1";
      return;
    }
    let program: WebGLProgram;
    try {
      program = gl.createProgram()!;
      gl.attachShader(program, compile(gl, gl.VERTEX_SHADER, VERT));
      gl.attachShader(program, compile(gl, gl.FRAGMENT_SHADER, FRAG));
      gl.linkProgram(program);
      if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error("link");
    } catch (err) {
      console.warn("voice glow shader unavailable:", err);
      el.dataset.fallback = "1";
      return;
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
      size: loc("size"), radius: loc("radius"), dpr: loc("dpr"), time: loc("time"), level: loc("level"), low: loc("low"),
      mid: loc("mid"), high: loc("high"), processing: loc("processing"), motion: loc("motion"), intensity: loc("intensity"),
    };
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    // Smoothed state, as the display's: fast attack, slower release, eased beam.
    const st = { time: 0, level: 0, low: 0, mid: 0, high: 0, process: 0 };
    const follow = (cur: number, target: number, dt: number) => cur + (target - cur) * Math.min(1, (target > cur ? 14 : 3.2) * dt);
    let last = performance.now();
    let frame = 0;
    const draw = (now: number) => {
      frame = requestAnimationFrame(draw);
      const dt = Math.min((now - last) / 1000, 0.1);
      last = now;
      st.time += dt;
      const inp = input.current;
      let level = inp?.level ?? 0;
      let low = inp?.low ?? level;
      let mid = inp?.mid ?? level;
      let high = inp?.high ?? level;
      if (inp?.speaking) {
        level = 0.35 + 0.35 * Math.abs(Math.sin(st.time * 7.3)) * (0.6 + 0.4 * Math.sin(st.time * 1.7));
        low = level * (0.9 + 0.1 * Math.sin(st.time * 2.3));
        mid = level;
        high = level * (0.7 + 0.3 * Math.abs(Math.sin(st.time * 5.1)));
      }
      st.level = follow(st.level, level, dt);
      st.low = follow(st.low, low, dt);
      st.mid = follow(st.mid, mid, dt);
      st.high = follow(st.high, high, dt);
      st.process += ((inp?.processing ? 1 : 0) - st.process) * Math.min(1, 2.6 * dt);

      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      const w = el.clientWidth;
      const h = el.clientHeight;
      if (el.width !== Math.round(w * dpr) || el.height !== Math.round(h * dpr)) {
        el.width = Math.round(w * dpr);
        el.height = Math.round(h * dpr);
      }
      gl.viewport(0, 0, el.width, el.height);
      gl.uniform2f(U.size, w, h);
      gl.uniform1f(U.radius, radius);
      gl.uniform1f(U.dpr, dpr);
      gl.uniform1f(U.time, st.time);
      gl.uniform1f(U.level, st.level);
      gl.uniform1f(U.low, st.low);
      gl.uniform1f(U.mid, st.mid);
      gl.uniform1f(U.high, st.high);
      gl.uniform1f(U.processing, st.process);
      gl.uniform1f(U.motion, reduce ? 0 : 1);
      gl.uniform1f(U.intensity, intensity);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    };
    frame = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(frame);
  }, [input, radius, intensity]);

  return (
    <canvas
      ref={canvas}
      aria-hidden="true"
      className={className}
      // Additive over the dark page, as on the display.
      style={{ mixBlendMode: "screen" }}
    />
  );
}
