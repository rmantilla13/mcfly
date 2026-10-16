// The sky backdrops' shaders (SkyBackdrop.tsx), in GLSL ES 1.00 for WebGL:
// the display's display/shaders/{arc,ribbons,dawn,silk,pillars}.frag line for
// line. Each is the same uniforms (plain here, Qt's block there), the shared
// functions (the simplex noise, the hash for the dither, the four-stop ramp
// picked by comparison since GLSL ES 1.00 only promises constant indices,
// OKLab out to sRGB), the style's own scene(), and a main() that differs only
// in where the pixel comes from (gl_FragCoord rather than qt_TexCoord0) and
// in writing gl_FragColor. tests/sky.test.mjs holds the scene bodies and the
// shared functions to the .frag files, so a change to a sky lands on both.
// Pure and without imports, so the test can load it.
//
// Per pixel: arc 5 simplex noise, ribbons 9, dawn 2, silk none (sines only),
// pillars 4; one OKLab -> sRGB and two hashes each.

import type { SkyStyle } from "@/lib/sky";

export const SKY_VERTEX = `attribute vec2 aPosition;
void main() {
  gl_Position = vec4(aPosition, 0.0, 1.0);
}`;

// The uniforms, named as the display's (Backdrop.qml feeds the same ones).
// `size` is the canvas in pixels here, where the display's is logical px:
// only the aspect is read from it.
const UNIFORMS = `#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
uniform vec2 size;         // canvas size, px
uniform float time;        // seconds x speed
uniform float strength;    // 0..1: how much of the light lands on the canvas
uniform float seed;        // picks a different sky
uniform float dim;         // the opacity applied after this shader (the dither is scaled to it)
uniform vec4 canvas;       // the canvas, OKLab (L, a, b)
uniform vec4 s0;           // the glow stops, OKLCh (L, C, hue in radians), hues unwrapped
uniform vec4 s1;
uniform vec4 s2;
uniform vec4 s3;`;

// arc.frag's (tri() is ribbons.frag's), shared by every style.
export const SKY_FUNCTIONS = `vec3 permute(vec3 x)
{
    return mod(((x * 34.0) + 1.0) * x, 289.0);
}

float snoise(vec2 v)
{
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

float hash(vec2 p)
{
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float tri(float x)
{
    return abs(fract(x) * 2.0 - 1.0);
}

vec3 lch2lab(vec3 c)
{
    return vec3(c.x, c.y * cos(c.z), c.y * sin(c.z));
}

vec3 ramp(float t)
{
    float x = clamp(t, 0.0, 1.0) * 3.0;
    float i = min(floor(x), 2.0);
    float f = x - i;
    f = f * f * (3.0 - 2.0 * f);
    vec3 a = s0.xyz;
    vec3 b = s1.xyz;
    if (i > 0.5) { a = s1.xyz; b = s2.xyz; }
    if (i > 1.5) { a = s2.xyz; b = s3.xyz; }
    return lch2lab(mix(a, b, f));
}

vec3 oklabToSrgb(vec3 c)
{
    vec3 lms = vec3(c.x + 0.3963377774 * c.y + 0.2158037573 * c.z,
                    c.x - 0.1055613458 * c.y - 0.0638541728 * c.z,
                    c.x - 0.0894841775 * c.y - 1.2914855480 * c.z);
    lms = lms * lms * lms;
    vec3 rgb = vec3( 4.0767416621 * lms.x - 3.3077115913 * lms.y + 0.2309699292 * lms.z,
                    -1.2684380046 * lms.x + 2.6097574011 * lms.y - 0.3413193965 * lms.z,
                    -0.0041960863 * lms.x - 0.7034186147 * lms.y + 1.7076147010 * lms.z);
    rgb = clamp(rgb, 0.0, 1.0);
    return mix(12.92 * rgb, 1.055 * pow(rgb, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, rgb));
}`;

// Each style's scene(): the picture's colour (OKLab) and how much of it
// there is, at uv (y up, 0 at the bottom edge).
export const SKY_SCENES: Readonly<Record<SkyStyle, string>> = {
  arc: `void scene(vec2 uv, float aspect, out vec3 lab, out float a)
{
    float X = (uv.x - 0.5) * aspect;
    float Y = uv.y;
    float t = time;
    // The arc's lower border: a curve, higher in the middle, bending slowly.
    float yc = 0.42 + 0.10 * cos(X * 0.9) + 0.07 * snoise(vec2(X * 0.6 + seed, t * 0.03));
    float d = Y - yc;
    // Bright at the border, a quick fall, then a long faint tail upward.
    float up = max(d, 0.0);
    float body = smoothstep(-0.03, 0.01, d) * (0.45 * exp(-up * 24.0) + 0.55 * exp(-up * 7.5));
    // Rays: a tall noise folded by a slow warp.
    float warp = snoise(vec2(X * 1.2, t * 0.04 + seed));
    float r = snoise(vec2(X * 14.0 + warp * 1.4, Y * 0.5 + t * 0.06));
    float rays = 0.5 + 0.5 * r;
    // Brightness travelling along the arc.
    float along = 0.4 + 0.6 * (0.5 + 0.5 * snoise(vec2(X * 1.1 - t * 0.05, 7.0 + seed)));
    a = body * (0.55 + 0.45 * rays) * along * 1.25;
    // A second, fainter arc behind.
    float yc2 = yc + 0.24 + 0.05 * snoise(vec2(X * 0.5, t * 0.02 + 11.0));
    float d2 = Y - yc2;
    a += 0.3 * smoothstep(-0.05, 0.02, d2) * exp(-max(d2, 0.0) * 12.0) * (0.6 + 0.4 * r);
    // The first stop along the border, the others up through the rays.
    lab = ramp(clamp(up * 2.2, 0.0, 1.0) * 0.8 + 0.1 * warp + 0.1);
}`,
  ribbons: `void scene(vec2 uv, float aspect, out vec3 lab, out float a)
{
    float X = (uv.x - 0.5) * aspect;
    float Y = uv.y;
    float t = time;
    a = 0.0;
    lab = vec3(0.0);
    float ws = 0.0;
    for (int k = 0; k < 3; k++) {
        float fk = float(k);
        // Where the ribbon runs, how wide it is, and where it folds toward us.
        float yk = 0.30 + 0.18 * fk
                 + 0.09 * snoise(vec2(X * 0.7 + fk * 7.3 + seed, t * 0.035 + fk))
                 + 0.03 * sin(X * 2.2 + t * 0.08 + fk * 2.0);
        float w = 0.018 + 0.02 * (0.5 + 0.5 * snoise(vec2(X * 1.4 + fk * 3.0, t * 0.03 + fk * 5.0)));
        float dy = (Y - yk) / w;
        float core = exp(-dy * dy);
        float halo = 0.28 * exp(-dy * dy * 0.06);
        float fold = 0.55 + 0.45 * snoise(vec2(X * 2.4 - t * 0.05, fk * 4.0 + seed));
        float ak = (core + halo) * fold * (1.0 - 0.25 * fk);
        vec3 lk = ramp(tri(uv.x * 0.45 + fk * 0.3 + t * 0.004));
        lab += lk * ak;
        ws += ak;
        a = 1.0 - (1.0 - a) * (1.0 - ak);   // screened, one behind the other
    }
    lab /= max(ws, 1e-4);
}`,
  dawn: `void scene(vec2 uv, float aspect, out vec3 lab, out float a)
{
    float X = (uv.x - 0.5) * aspect;
    float Y = uv.y;
    float t = time;
    // The height above the horizon, swaying a little.
    float h = Y + 0.05 * sin(X * 1.3 + t * 0.045)
            + 0.035 * snoise(vec2(X * 0.8 + seed, t * 0.02 + Y * 1.5));
    float haze = 0.5 + 0.5 * snoise(vec2(X * 1.8 + t * 0.025, h * 5.0 + seed));
    // The sun's glow sits low and wanders.
    float sx = 0.25 * sin(t * 0.013);
    float sun = exp(-((X - sx) * (X - sx) * 1.6 + (h - 0.08) * (h - 0.08) * 9.0));
    // The first stop overhead, the last at the horizon and in the sun.
    lab = ramp(clamp(1.0 - h * 1.15 + 0.08 * haze - 0.35 * sun, 0.0, 1.0));
    a = 0.55 + 0.45 * (1.0 - h);
    a *= 0.82 + 0.18 * haze;
    a = min(a + 0.3 * sun, 1.0);
}`,
  silk: `void scene(vec2 uv, float aspect, out vec3 lab, out float a)
{
    float X = (uv.x - 0.5) * aspect;
    float Y = uv.y;
    float t = time;
    a = 0.0;
    lab = vec3(0.0);
    float ws = 0.0;
    for (int k = 0; k < 2; k++) {
        float fk = float(k);
        // The sheet's folds: a few sines, each sheet out of step with the other.
        float v = Y * 2.6 + 0.55 * sin(X * 1.6 + t * 0.06 + fk * 1.7)
                + 0.35 * sin(X * 3.3 - t * 0.045 + Y * 2.2 + fk)
                + 0.25 * sin((X + Y) * 4.1 + t * 0.03 + fk * 3.0);
        float fold = sin(v * 2.4 + fk * 1.3 + seed);
        float shade = 0.5 + 0.5 * fold;
        float sheen = pow(max(fold, 0.0), 8.0);
        float ak = (0.35 + 0.45 * shade + 0.5 * sheen) * (1.0 - 0.4 * fk);
        vec3 lk = ramp(clamp(uv.x * 0.55 + 0.25 * fold + 0.15 + fk * 0.15, 0.0, 1.0));
        lab += lk * ak;
        ws += ak;
        a = 1.0 - (1.0 - a) * (1.0 - ak * 0.8);
    }
    lab /= max(ws, 1e-4);
}`,
  pillars: `void scene(vec2 uv, float aspect, out vec3 lab, out float a)
{
    float X = (uv.x - 0.5) * aspect;
    float Y = uv.y;
    float t = time;
    float warp = snoise(vec2(X * 0.9 + seed, t * 0.03));
    // Noise that varies along X only: columns.
    float col = snoise(vec2(X * 4.5 + warp * 0.7, t * 0.05));
    float fine = snoise(vec2(X * 11.0 - warp * 0.4, t * 0.08 + 5.0));
    float pillar = pow(0.5 + 0.5 * col, 2.2) * (0.7 + 0.3 * fine);
    // How far up the row the light reaches.
    float reach = 0.35 + 0.35 * (0.5 + 0.5 * snoise(vec2(X * 1.3 + 9.0, t * 0.04)));
    float rise = smoothstep(0.0, 0.06, Y) * exp(-Y / reach * 2.0);
    a = pillar * rise * 1.4;
    lab = ramp(clamp(Y * 1.3 + 0.1 * warp, 0.0, 1.0));
}`,
};

// The display's main(), with the pixel from gl_FragCoord (y up, as the
// display's flipped qt_TexCoord0 is).
const MAIN = `void main()
{
    vec2 uv = gl_FragCoord.xy / size;
    float aspect = size.x / max(size.y, 1.0);
    vec3 lab;
    float a;
    scene(uv, aspect, lab, a);
    a = clamp(a, 0.0, 1.0) * strength;
    vec3 col = oklabToSrgb(mix(canvas.xyz, lab, a));
    // Triangular dither, one step of the final picture: the opacity comes
    // after it, so it is scaled up by as much.
    vec2 cell = floor(gl_FragCoord.xy);
    col += (hash(cell) + hash(cell + 17.13) - 1.0) / 255.0 / max(dim, 0.1);
    gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}`;

export function skyFragment(style: SkyStyle): string {
  return [UNIFORMS, SKY_FUNCTIONS, SKY_SCENES[style], MAIN].join("\n\n");
}
