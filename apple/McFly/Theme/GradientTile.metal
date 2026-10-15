// GradientTile (GradientTile.swift), "Poster glow": the display's
// display/shaders/gradienttile.frag as a SwiftUI colour effect. A luminous
// pastel mesh gradient with one or two frosted-glass rings drifting across
// it, blurred into the gradient, under a static film grain. One pass, no
// textures, no loops. The rounded corners are SwiftUI's clip, not ours.
//
// Per pixel: 8 exp, ~5 smoothstep/clamp, 4 length, 2 hash.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

namespace {

float hash12(float2 p)
{
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float blob(float2 p, float2 c, float inv)
{
    float2 d = p - c;
    return exp(-dot(d, d) * inv);
}

} // namespace

// size: the tile, in points. phase: the loop clock, 0..2pi plus the seed's
// offset (all motion uses whole multiples of it). seed: per-tile variation.
// rings: 0, 1 or 2. ringScale, ringBias: the rings' size and horizontal home.
// glass: rim and frost strength (dimmed at night). grain: film-grain amplitude.
// soft: 0 = crisp glass edges, 1 = blurred into the gradient. dpr: pixels per
// point, so the grain is one value per pixel. pal: four palette colours, then
// the rim colour, as sRGB triples, then the rim's strength (16 floats).
[[ stitchable ]] half4 gradientTile(float2 position, half4 color, float2 size, float phase, float seed,
                                   float rings, float ringScale, float ringBias, float glass, float grain,
                                   float soft, float dpr, device const float *pal, int count)
{
    if (count < 16 || size.x <= 0.0 || size.y <= 0.0) {
        return color;
    }
    float2 p = position;
    float2 uv = p / size;
    float px = 1.0 / dpr;
    float t = phase;
    float s = seed;
    float motion = 1.0;
    float flip = step(0.5, fract(s * 0.618034));   // mirror the layout on half the seeds

    float3 c0 = float3(pal[0], pal[1], pal[2]);
    float3 c1 = float3(pal[3], pal[4], pal[5]);
    float3 c2 = float3(pal[6], pal[7], pal[8]);
    float3 c3 = float3(pal[9], pal[10], pal[11]);
    float3 rim = float3(pal[12], pal[13], pal[14]);
    float rimAlpha = pal[15];

    // ---- Glass rings (geometry first: they bend the gradient behind them).
    float R1 = ringScale * min(0.40 * size.x, 1.05 * size.y);
    float R2 = 0.72 * R1;
    float bias = mix(ringBias, 1.0 - ringBias, flip);
    float2 home = float2(size.x * bias, size.y * 0.42);
    float side = mix(-1.0, 1.0, flip);                // ring 2 sits toward the tile centre
    float ax = 0.30 * R1 + 0.05 * size.x;            // drift reach
    float2 r1c = home + motion * float2(ax * sin(t + s * 2.1), 0.22 * R1 * sin(2.0 * t + s * 3.7));
    float2 r2c = home + float2(0.55 * side * R1, 0.62 * R1)
               + motion * float2(ax * cos(t + s * 1.3 + 1.9), 0.26 * R1 * sin(t + s * 0.9 + 0.6));

    float2 d1 = p - r1c;
    float2 d2 = p - r2c;
    float l1 = length(d1);
    float l2 = length(d2);
    float on1 = step(0.5, rings);
    float on2 = step(1.5, rings);
    // Edge width: one pixel when crisp, 7% of the radius when soft.
    float ew1 = max(px, soft * 0.07 * R1);
    float ew2 = max(px, soft * 0.07 * R2);
    float in1 = on1 * (1.0 - smoothstep(R1 - ew1, R1 + ew1, l1));
    float in2 = on2 * (1.0 - smoothstep(R2 - ew2, R2 + ew2, l2));

    // Lens: inside a ring the gradient is sampled slightly magnified and
    // shifted, so the ring reads as glass; overlaps bend twice.
    float lens = 1.0 - 0.35 * soft;
    float2 ps = p - lens * in1 * (0.14 * d1 + float2(0.07, -0.05) * R1)
                  - lens * in2 * (0.14 * d2 + float2(-0.05, 0.07) * R2);

    // ---- Mesh gradient: three drifting colour fields + a soft highlight.
    float S = sqrt(size.x * size.y);
    float inv = 1.0 / (0.34 * S * S);
    float2 a0 = float2(mix(0.10, 0.90, flip), 0.10);
    float2 a1 = float2(mix(0.90, 0.10, flip), 0.30);
    float2 a2 = float2(0.45, 1.00);
    float2 a3 = float2(mix(0.62, 0.38, flip), 0.62);
    float2 b0 = size * (a0 + motion * float2(0.10 * sin(t + s), 0.18 * cos(t + s * 1.7)));
    float2 b1 = size * (a1 + motion * float2(0.12 * cos(2.0 * t + s * 2.3), 0.20 * sin(t + s * 0.7)));
    float2 b2 = size * (a2 + motion * float2(0.18 * sin(-t + s * 1.1), 0.15 * cos(2.0 * t + s * 2.9)));
    float2 b3 = size * (a3 + motion * float2(0.20 * cos(t + s * 3.1), 0.22 * sin(-2.0 * t + s * 1.9)));

    float w0 = blob(ps, b0, inv) + 0.02;
    float w1 = blob(ps, b1, inv);
    float w2 = blob(ps, b2, inv * 1.2);
    float3 col = (c0 * w0 + c1 * w1 + c2 * w2) / (w0 + w1 + w2);
    col = mix(col, c3, 0.62 * blob(ps, b3, inv * 2.4));

    // Faint top sheen, like light on a glass sheet.
    col += glass * 0.035 * (1.0 - uv.y);

    // ---- Frost: a faint fill that brightens toward the rim; tint the overlap.
    float e1 = min(l1 / max(R1, 1.0), 1.0);
    float e2 = min(l2 / max(R2, 1.0), 1.0);
    float toRim = 0.16 * (1.0 - 0.55 * soft);
    float frost = in1 * (0.07 + toRim * e1 * e1 * e1) + in2 * (0.07 + toRim * e2 * e2 * e2);
    col = mix(col, c2, 0.30 * in1 * in2);
    col = mix(col, rim, glass * glass * frost);

    // ---- Rims: a ridge across the ring's edge, lit from the top-left, with a halo.
    float2 L = float2(-0.6, -0.8);
    float g1 = abs(l1 - R1);
    float g2 = abs(l2 - R2);
    float k1 = max(0.55 + 0.5 * px, soft * 0.03 * R1);
    float k2 = max(0.55 + 0.5 * px, soft * 0.03 * R2);
    float rim1 = on1 * exp(-g1 * g1 / (k1 * k1)) * (0.6 + 0.4 * dot(d1 / max(l1, 0.001), L));
    float rim2 = on2 * exp(-g2 * g2 / (k2 * k2)) * (0.6 + 0.4 * dot(d2 / max(l2, 0.001), L));
    float h1 = max(4.0, soft * 0.10 * R1);
    float h2 = max(4.0, soft * 0.10 * R2);
    float halo = on1 * exp(-g1 * g1 / (h1 * h1)) + on2 * exp(-g2 * g2 / (h2 * h2));
    float lines = (1.0 - 0.5 * soft) * (rim1 + rim2) + (0.22 - 0.06 * soft) * halo;
    col = mix(col, rim, glass * rimAlpha * clamp(lines, 0.0, 1.0));

    // ---- Film grain: static, one value per physical pixel, from two hashes
    // so it clusters around zero like real grain.
    float2 gp = floor(p * dpr);
    col += (hash12(gp) + hash12(gp.yx * 1.618 + 71.3) - 1.0) * grain;

    col = clamp(col, 0.0, 1.0);
    return half4(half3(col) * color.a, color.a);
}
