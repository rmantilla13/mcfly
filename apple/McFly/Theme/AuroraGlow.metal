// AuroraGlow (AuroraGlow.swift): a curtain of light hanging from the top edge,
// its hem rolling on layered simplex noise, its colour running left to right
// through 2-5 stops blended in OKLCh. One pass, no textures: a SwiftUI colour
// effect.
//
// Ported from React Bits' Aurora (https://github.com/DavidHDev/react-bits,
// src/ts-tailwind/Backgrounds/Aurora, commit 963f4d2), the same shader the
// display draws (display/shaders/aurora.frag) and the console
// (admin/components/reactbits/Aurora.tsx).
//
// MIT + Commons Clause License Condition v1.0
//
// Copyright (c) 2026 David Haz
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, and distribute the Software as part of
// an application, website, or product, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// Commons Clause Restriction: You may use this Software, including for any
// commercial purpose, so long as you do not sell, sublicense, or redistribute the
// components themselves-whether alone, in a bundle, or as a ported version.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
// Changes for SwiftUI: the view's own coordinates (`position`, points, y down,
// as qt_TexCoord0) for the curtain; the colour stops are one float array
// (OKLCh triples, converted in Swift) and ramp() indexes it, since Metal has
// none of GLSL ES 1.00's limits; GLSL's mod() is written out, since Metal's
// fmod() rounds toward zero and the noise runs on negative coordinates; the
// opacity is applied here, as the console's uOpacity is, and the dither is
// one step of the final picture; its cells are pixels (`dpr` per point); the
// pointer's pull is gone (a phone has no hover).
//
// Kept line for line with display/shaders/aurora.frag otherwise: the hem
// folds through a 2D domain warp; faint rays run down the curtain (`rays`, 0
// skips their noise); the hue sways on noise worked out in Swift (`drift`);
// light mode is ink on the canvas, eased (`lightMode` 0..1, the two looks
// blended); triangular dither.
//
// Per pixel and layer: 5 simplex noise (4 with rays off), 1 OKLCh -> sRGB,
// ~5 smootherstep, 1 pow.

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

float smootherstep(float edge0, float edge1, float x)
{
    float t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

float3 oklabToLinear(float3 c)
{
    float l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
    float m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
    float s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
    l = l * l * l;
    m = m * m * m;
    s = s * s * s;
    return float3(
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    );
}

float3 toSrgb(float3 c)
{
    c = saturate(c);
    return mix(c * 12.92, 1.055 * pow(c, float3(1.0 / 2.4)) - 0.055, step(float3(0.0031308), c));
}

// The pair of stops either side of t, straight from the array (OKLCh
// triples, 2-5 of them; count is the number of floats).
float3 ramp(float t, device const float *stops, int count)
{
    float n = clamp(float(count / 3), 2.0, 5.0);
    float x = saturate(t) * (n - 1.0);
    float i = min(floor(x), n - 2.0);
    float f = x - i;
    f = f * f * (3.0 - 2.0 * f);
    int k = int(i) * 3;
    float3 a = float3(stops[k], stops[k + 1], stops[k + 2]);
    float3 b = float3(stops[k + 3], stops[k + 4], stops[k + 5]);
    float3 lch = mix(a, b, f);
    return toSrgb(oklabToLinear(float3(lch.x, lch.y * cos(lch.z), lch.y * sin(lch.z))));
}

float hash(float2 p)
{
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

} // namespace

// size: the view, in points. time: seconds x speed. reveal: 0..1, eased (the
// curtain lowers into place; 1 when there's no intro). amplitude: how tall the
// waves along the hem are. blend: 0..1, how softly the hem fades out. hem:
// 0..1, where the hem rests (from the top). waveScale: horizontal frequency of
// the waves. glow: how far the light spills past the hem. brightness: 0..2.
// layers: 1..3. flip: 1 hangs it from the bottom instead. lightMode: 0..1,
// eased: 0 light over a dark canvas, 1 ink on a light one. rays: 0..1, how
// strong the rays are; 0 skips them. opacity: the picture's. dpr: pixels per
// point, so the dither is one value per pixel. drift: the hue's sway, per
// layer. stops: the colour stops, OKLCh (L, C, hue in radians), unwrapped.
[[ stitchable ]] half4 auroraGlow(float2 position, half4 color, float2 size, float time, float reveal,
                                 float amplitude, float blend, float hem, float waveScale, float glow,
                                 float brightness, float layers, float flip, float lightMode, float rays,
                                 float opacity, float dpr, float3 drift, device const float *stops, int count)
{
    if (count < 6 || size.x <= 0.0 || size.y <= 0.0) {
        return half4(0.0);
    }
    float2 uv = position / size;
    float y = mix(uv.y, 1.0 - uv.y, flip);   // 0 at the edge it hangs from
    float u = uv.x;
    float X = (position.x - size.x * 0.5) / max(size.y, 1.0);
    float t = time;

    float3 light = float3(0.0);   // over a dark sky: the layers screened, premultiplied
    float cover = 0.0;
    float3 ink = float3(1.0);     // on a light canvas: what the layers let through, multiplied
    for (int k = 0; k < 3; k++) {
        if (float(k) >= layers)
            break;
        float layer = float(k);
        float seed = layer * 13.7;
        float pace = t * (1.0 - layer * 0.18);
        // A slow 2D warp that the hem folds through: it bends the waves in
        // place and in time, so nothing slides along X at a steady rate.
        float2 q = float2(X * 0.45 * waveScale, pace * 0.035 + seed);
        float2 w = float2(snoise(q), snoise(q + float2(5.2, 1.3)));
        float wave = snoise(float2(X * 0.75 * waveScale, pace * 0.05 - seed) + w * 0.35) * 0.72
                   + snoise(float2(X * 1.6 * waveScale, pace * 0.09 + seed * 0.5) + w * 0.5) * 0.28;
        float edge = hem + layer * 0.07 + wave * 0.15 * amplitude;
        edge = mix(-0.25, edge, reveal);

        float soft = (0.04 + blend * 0.16) * (1.0 + layer * 0.9);
        float rise = edge - y;
        float low = -soft - glow * 0.14;
        float high = 0.26 + soft * 0.6;
        float body = pow(smootherstep(low, high, rise), 1.5 + glow * 0.6);
        float alpha = body * (0.86 + 0.14 * w.y) * (layer < 0.5 ? 1.0 : 0.32 / layer);
        // Rays: soft streaks along the fall of the curtain (a noise stretched
        // tall), bent by the same warp, gathered where the warp says, and
        // strongest just above the hem. They only take light away.
        if (rays > 0.0) {
            float n = snoise(float2(X * 7.0 * waveScale + w.x * 2.0, y * 0.5 + pace * 0.1 - seed));
            float along = smootherstep(-0.1, 0.1, rise) * (1.0 - 0.6 * smootherstep(0.1, 0.5, rise));
            float gather = smootherstep(-0.3, 0.5, w.y);
            alpha *= 1.0 - rays * 0.22 * n * n * along * gather;
        }
        alpha = clamp(alpha, 0.0, 1.0);

        float sway = layer < 0.5 ? drift.x : (layer < 1.5 ? drift.y : drift.z);
        float3 tint = ramp(u + sway + layer * 0.1 + max(rise, 0.0) * 0.05, stops, count);
        light = 1.0 - (1.0 - light) * (1.0 - tint * alpha);
        cover = 1.0 - (1.0 - cover) * (1.0 - alpha);
        // As ink the colour is a filter: its own channel passes in full, so
        // the canvas is tinted, never greyed.
        ink *= 1.0 - alpha * (1.0 - tint / max(max(tint.r, tint.g), max(tint.b, 0.001)));
    }

    float strength = clamp(brightness, 0.0, 2.0);
    float gain = smootherstep(0.0, 0.7, reveal) * min(strength, 1.0);
    float4 onDark = float4(1.0 - pow(1.0 - light * gain, float3(max(strength, 1.0))), cover * gain);
    // Ink laid on with a plain "over": the alpha is the most a channel
    // absorbs and the colour what the others keep, which on a light canvas
    // comes out as a multiply. A faint tail is held back so it doesn't stain.
    float3 absorb = (1.0 - pow(ink, float3(max(strength, 1.0)))) * gain * smootherstep(0.0, 0.25, cover * gain) * 0.7;
    float inked = max(absorb.r, max(absorb.g, absorb.b));
    float4 col = mix(onDark, float4(inked - absorb, inked), lightMode);

    // Triangular dither, one step of the final picture: the opacity comes
    // after it, so it is scaled up by as much. Only where there is light.
    float2 cell = floor(position * dpr);
    float dither = (hash(cell) + hash(cell + 17.13) - 1.0) / 255.0;
    col += dither / max(opacity, 0.1) * min(col.a * 255.0, 1.0);
    return half4(saturate(col) * opacity) * color.a;
}
