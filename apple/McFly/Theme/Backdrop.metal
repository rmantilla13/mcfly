// Backdrop (Backdrop.swift): the display's five skies for the screen savers,
// display/shaders/{arc,ribbons,dawn,silk,pillars}.frag as SwiftUI colour
// effects, one function each. Arc: an aurora band curving across the sky,
// bright along its lower edge, rays running up through it. Ribbons: three
// thin curtains edge-on, folding. Dawn: a horizon gradient, a low sun glow,
// haze. Silk: two sheets of satin folding over each other. Pillars: columns
// of light standing up from the bottom edge. One pass, no textures.
//
// Shared by all five, as on the display: the glow stops arrive in OKLCh with
// the hues unwrapped (Backdrop.swift) and ramp() blends the pair either side
// of t; the light is laid on the canvas by an OKLab mix (`strength` says how
// much), a pastel wash on the warm canvas by day and a glow on the near-black
// one at night; triangular dither, one step of the final picture. The
// simplex noise and the OKLab conversion are aurora.frag's (AuroraGlow.metal
// has the same).
//
// Changes for SwiftUI: the view's own coordinates (`position`, points, y
// down) are turned into the shaders' uv (y up from the bottom edge); the stops
// are one float array (OKLCh triples) and ramp() indexes it, since Metal has
// none of GLSL ES 1.00's limits; GLSL's mod() is written out, since Metal's
// fmod() rounds toward zero and the noise runs on negative coordinates; the
// dither's cells are pixels (`dpr` per point); the display's `dim` is gone,
// since here the sky is always drawn in full. The scene() functions are kept
// line for line.
//
// Per pixel: arc 5 simplex noise; ribbons 9 (3 a ribbon, the dearest, so
// Backdrop.swift runs it at 0.4 of the view's size); dawn 2; silk none (8 sin,
// 1 pow); pillars 4 and 1 pow. Each also 1 OKLab -> sRGB and 2 hash.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

namespace {

// GLSL's mod(x, 289.0): the result takes the divisor's sign.
float2 mod289(float2 x)
{
    return x - 289.0 * floor(x / 289.0);
}

float3 mod289(float3 x)
{
    return x - 289.0 * floor(x / 289.0);
}

float3 permute(float3 x)
{
    return mod289(((x * 34.0) + 1.0) * x);
}

float snoise(float2 v)
{
    const float4 C = float4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
    float2 i = floor(v + dot(v, C.yy));
    float2 x0 = v - i + dot(i, C.xx);
    float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;
    i = mod289(i);
    float3 p = permute(permute(i.y + float3(0.0, i1.y, 1.0)) + i.x + float3(0.0, i1.x, 1.0));
    float3 m = max(0.5 - float3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), float3(0.0));
    m = m * m;
    m = m * m;
    float3 x = 2.0 * fract(p * C.www) - 1.0;
    float3 h = abs(x) - 0.5;
    float3 ox = floor(x + 0.5);
    float3 a0 = x - ox;
    m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
    float3 g;
    g.x = a0.x * x0.x + h.x * x0.y;
    g.yz = a0.yz * x12.xz + h.yz * x12.yw;
    return 130.0 * dot(m, g);
}

float hash(float2 p)
{
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// 0..1..0 as x goes 0..1, so a ramp driven by it has no seam.
float tri(float x)
{
    return abs(fract(x) * 2.0 - 1.0);
}

float3 lch2lab(float3 c)
{
    return float3(c.x, c.y * cos(c.z), c.y * sin(c.z));
}

// The four stops blended in OKLCh, t 0..1 from the first to the last: the
// pair either side of t, straight from the array (OKLCh triples, 12 floats).
float3 ramp(float t, device const float *stops)
{
    float x = saturate(t) * 3.0;
    float i = min(floor(x), 2.0);
    float f = x - i;
    f = f * f * (3.0 - 2.0 * f);
    int k = int(i) * 3;
    float3 a = float3(stops[k], stops[k + 1], stops[k + 2]);
    float3 b = float3(stops[k + 3], stops[k + 4], stops[k + 5]);
    return lch2lab(mix(a, b, f));
}

float3 oklabToSrgb(float3 c)
{
    float3 lms = float3(c.x + 0.3963377774 * c.y + 0.2158037573 * c.z,
                        c.x - 0.1055613458 * c.y - 0.0638541728 * c.z,
                        c.x - 0.0894841775 * c.y - 1.2914855480 * c.z);
    lms = lms * lms * lms;
    float3 rgb = float3( 4.0767416621 * lms.x - 3.3077115913 * lms.y + 0.2309699292 * lms.z,
                        -1.2684380046 * lms.x + 2.6097574011 * lms.y - 0.3413193965 * lms.z,
                        -0.0041960863 * lms.x - 0.7034186147 * lms.y + 1.7076147010 * lms.z);
    rgb = saturate(rgb);
    return mix(12.92 * rgb, 1.055 * pow(rgb, float3(1.0 / 2.4)) - 0.055, step(float3(0.0031308), rgb));
}

// The shaders' uv: x across, y up from the bottom edge.
float2 skyUV(float2 position, float2 size)
{
    return float2(position.x / size.x, 1.0 - position.y / size.y);
}

// What every sky ends with: the picture (its colour in OKLab and how much of
// it there is) laid on the canvas, `strength` saying how much lands, then one
// step of triangular dither per pixel.
half4 finish(float2 position, half4 color, float strength, float dpr, float3 canvas, float3 lab, float a)
{
    a = saturate(a) * strength;
    float3 col = oklabToSrgb(mix(canvas, lab, a));
    float2 cell = floor(position * dpr);
    col += (hash(cell) + hash(cell + 17.13) - 1.0) / 255.0;
    return half4(half3(saturate(col)) * color.a, color.a);
}

} // namespace

// Every sky takes the same uniforms (names as in the display's shaders).
// size: the view, in points. time: seconds x speed. strength: 0..1, how much
// of the light lands on the canvas. seed: picks a different sky. dpr: pixels
// per point, so the dither is one value per pixel. canvas: the canvas, OKLab
// (L, a, b). stops: the four glow stops, OKLCh (L, C, hue in radians), hues
// unwrapped; count is the number of floats (12).

// Arc: an aurora as seen from the ground. A band curves across the sky,
// bright along its lower edge and thinning upward, rays run up through it,
// brightness travels along it, and a fainter arc hangs behind.
[[ stitchable ]] half4 backdropArc(float2 position, half4 color, float2 size, float time, float strength,
                                   float seed, float dpr, float3 canvas, device const float *stops, int count)
{
    if (count < 12 || size.x <= 0.0 || size.y <= 0.0) {
        return color;
    }
    float2 uv = skyUV(position, size);
    float aspect = size.x / max(size.y, 1.0);
    float X = (uv.x - 0.5) * aspect;
    float Y = uv.y;
    float t = time;
    // The arc's lower border: a curve, higher in the middle, bending slowly.
    float yc = 0.42 + 0.10 * cos(X * 0.9) + 0.07 * snoise(float2(X * 0.6 + seed, t * 0.03));
    float d = Y - yc;
    // Bright at the border, a quick fall, then a long faint tail upward.
    float up = max(d, 0.0);
    float body = smoothstep(-0.03, 0.01, d) * (0.45 * exp(-up * 24.0) + 0.55 * exp(-up * 7.5));
    // Rays: a tall noise folded by a slow warp.
    float warp = snoise(float2(X * 1.2, t * 0.04 + seed));
    float r = snoise(float2(X * 14.0 + warp * 1.4, Y * 0.5 + t * 0.06));
    float rays = 0.5 + 0.5 * r;
    // Brightness travelling along the arc.
    float along = 0.4 + 0.6 * (0.5 + 0.5 * snoise(float2(X * 1.1 - t * 0.05, 7.0 + seed)));
    float a = body * (0.55 + 0.45 * rays) * along * 1.25;
    // A second, fainter arc behind.
    float yc2 = yc + 0.24 + 0.05 * snoise(float2(X * 0.5, t * 0.02 + 11.0));
    float d2 = Y - yc2;
    a += 0.3 * smoothstep(-0.05, 0.02, d2) * exp(-max(d2, 0.0) * 12.0) * (0.6 + 0.4 * r);
    // The first stop along the border, the others up through the rays.
    float3 lab = ramp(clamp(up * 2.2, 0.0, 1.0) * 0.8 + 0.1 * warp + 0.1, stops);
    return finish(position, color, strength, dpr, canvas, lab, a);
}

// Ribbons: three thin curtains seen edge-on from far away, silk ribbons that
// fold and brighten where they turn, each carrying the glow left to right,
// one behind the other.
[[ stitchable ]] half4 backdropRibbons(float2 position, half4 color, float2 size, float time, float strength,
                                       float seed, float dpr, float3 canvas, device const float *stops, int count)
{
    if (count < 12 || size.x <= 0.0 || size.y <= 0.0) {
        return color;
    }
    float2 uv = skyUV(position, size);
    float aspect = size.x / max(size.y, 1.0);
    float X = (uv.x - 0.5) * aspect;
    float Y = uv.y;
    float t = time;
    float a = 0.0;
    float3 lab = float3(0.0);
    float ws = 0.0;
    for (int k = 0; k < 3; k++) {
        float fk = float(k);
        // Where the ribbon runs, how wide it is, and where it folds toward us.
        float yk = 0.30 + 0.18 * fk
                 + 0.09 * snoise(float2(X * 0.7 + fk * 7.3 + seed, t * 0.035 + fk))
                 + 0.03 * sin(X * 2.2 + t * 0.08 + fk * 2.0);
        float w = 0.018 + 0.02 * (0.5 + 0.5 * snoise(float2(X * 1.4 + fk * 3.0, t * 0.03 + fk * 5.0)));
        float dy = (Y - yk) / w;
        float core = exp(-dy * dy);
        float halo = 0.28 * exp(-dy * dy * 0.06);
        float fold = 0.55 + 0.45 * snoise(float2(X * 2.4 - t * 0.05, fk * 4.0 + seed));
        float ak = (core + halo) * fold * (1.0 - 0.25 * fk);
        float3 lk = ramp(tri(uv.x * 0.45 + fk * 0.3 + t * 0.004), stops);
        lab += lk * ak;
        ws += ak;
        a = 1.0 - (1.0 - a) * (1.0 - ak);   // screened, one behind the other
    }
    lab /= max(ws, 1e-4);
    return finish(position, color, strength, dpr, canvas, lab, a);
}

// Dawn: the boot splash grown up. A horizon gradient, the first stop at the
// top and the last at the horizon, a low sun glow wandering along it and
// haze drifting through.
[[ stitchable ]] half4 backdropDawn(float2 position, half4 color, float2 size, float time, float strength,
                                    float seed, float dpr, float3 canvas, device const float *stops, int count)
{
    if (count < 12 || size.x <= 0.0 || size.y <= 0.0) {
        return color;
    }
    float2 uv = skyUV(position, size);
    float aspect = size.x / max(size.y, 1.0);
    float X = (uv.x - 0.5) * aspect;
    float Y = uv.y;
    float t = time;
    // The height above the horizon, swaying a little.
    float h = Y + 0.05 * sin(X * 1.3 + t * 0.045)
            + 0.035 * snoise(float2(X * 0.8 + seed, t * 0.02 + Y * 1.5));
    float haze = 0.5 + 0.5 * snoise(float2(X * 1.8 + t * 0.025, h * 5.0 + seed));
    // The sun's glow sits low and wanders.
    float sx = 0.25 * sin(t * 0.013);
    float sun = exp(-((X - sx) * (X - sx) * 1.6 + (h - 0.08) * (h - 0.08) * 9.0));
    // The first stop overhead, the last at the horizon and in the sun.
    float3 lab = ramp(clamp(1.0 - h * 1.15 + 0.08 * haze - 0.35 * sun, 0.0, 1.0), stops);
    float a = 0.55 + 0.45 * (1.0 - h);
    a *= 0.82 + 0.18 * haze;
    a = min(a + 0.3 * sun, 1.0);
    return finish(position, color, strength, dpr, canvas, lab, a);
}

// Silk: two sheets of satin folding over each other. The folds catch a
// highlight where they turn toward us and shade where they turn away, and
// the glow runs across the weave. No noise: sines only.
[[ stitchable ]] half4 backdropSilk(float2 position, half4 color, float2 size, float time, float strength,
                                    float seed, float dpr, float3 canvas, device const float *stops, int count)
{
    if (count < 12 || size.x <= 0.0 || size.y <= 0.0) {
        return color;
    }
    float2 uv = skyUV(position, size);
    float aspect = size.x / max(size.y, 1.0);
    float X = (uv.x - 0.5) * aspect;
    float Y = uv.y;
    float t = time;
    float a = 0.0;
    float3 lab = float3(0.0);
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
        float3 lk = ramp(clamp(uv.x * 0.55 + 0.25 * fold + 0.15 + fk * 0.15, 0.0, 1.0), stops);
        lab += lk * ak;
        ws += ak;
        a = 1.0 - (1.0 - a) * (1.0 - ak * 0.8);
    }
    lab /= max(ws, 1e-4);
    return finish(position, color, strength, dpr, canvas, lab, a);
}

// Pillars: aurora rays seen close. Columns of light stand up from the bottom
// edge, each swelling and fading on its own, their reach rising and falling
// along the row; the glow climbs from the first stop at the ground to the
// last overhead.
[[ stitchable ]] half4 backdropPillars(float2 position, half4 color, float2 size, float time, float strength,
                                       float seed, float dpr, float3 canvas, device const float *stops, int count)
{
    if (count < 12 || size.x <= 0.0 || size.y <= 0.0) {
        return color;
    }
    float2 uv = skyUV(position, size);
    float aspect = size.x / max(size.y, 1.0);
    float X = (uv.x - 0.5) * aspect;
    float Y = uv.y;
    float t = time;
    float warp = snoise(float2(X * 0.9 + seed, t * 0.03));
    // Noise that varies along X only: columns.
    float col = snoise(float2(X * 4.5 + warp * 0.7, t * 0.05));
    float fine = snoise(float2(X * 11.0 - warp * 0.4, t * 0.08 + 5.0));
    float pillar = pow(0.5 + 0.5 * col, 2.2) * (0.7 + 0.3 * fine);
    // How far up the row the light reaches.
    float reach = 0.35 + 0.35 * (0.5 + 0.5 * snoise(float2(X * 1.3 + 9.0, t * 0.04)));
    float rise = smoothstep(0.0, 0.06, Y) * exp(-Y / reach * 2.0);
    float a = pillar * rise * 1.4;
    float3 lab = ramp(clamp(Y * 1.3 + 0.1 * warp, 0.0, 1.0), stops);
    return finish(position, color, strength, dpr, canvas, lab, a);
}
