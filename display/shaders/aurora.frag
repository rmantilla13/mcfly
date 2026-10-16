#version 440
// AuroraGlow (qml/components/AuroraGlow.qml): a curtain of light hanging from
// the top edge, its hem rolling on layered simplex noise, its colour running
// left to right through 2-5 stops blended in OKLCh. One pass, no textures.
// Built into a .qsb by qt_add_shaders.
//
// Ported from React Bits' Aurora (https://github.com/DavidHDev/react-bits,
// src/ts-tailwind/Backgrounds/Aurora, commit 963f4d2), the same shader the
// console draws (admin/components/reactbits/Aurora.tsx).
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
// Changes for Qt: item coordinates (qt_TexCoord0, y down) instead of
// gl_FragCoord; the colour stops are five vec4 uniforms (OKLCh, converted in
// QML) instead of a uniform array; the pointer's pull is gone (a touch screen
// has no hover); the opacity is the item's (qt_Opacity), applied to the
// premultiplied result.
//
// Per pixel and layer: 4 simplex noise, ~3 smootherstep, 1 pow.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;         // item size, logical px
    float dpr;         // device pixel ratio (for the dither)
    float time;        // seconds x speed
    float reveal;      // 0..1, eased: the curtain lowers into place
    float amplitude;   // how tall the waves along the hem are
    float blend;       // 0..1, how softly the hem fades out
    float hem;         // 0..1, where the hem rests (from the top)
    float waveScale;   // horizontal frequency of the waves
    float glow;        // how far the light spills past the hem
    float brightness;  // 0..2
    float layers;      // 1..3
    float flip;        // 1: hang from the bottom instead
    float lightMode;   // 1: a tint for a light canvas; 0: light over a dark one
    float stopCount;   // 2..5
    vec4 s0;           // colour stops, OKLCh (L, C, hue in radians), unwrapped
    vec4 s1;
    vec4 s2;
    vec4 s3;
    vec4 s4;
};

vec3 permute(vec3 x)
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

float smootherstep(float edge0, float edge1, float x)
{
    float t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

vec3 oklabToLinear(vec3 c)
{
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

vec3 toSrgb(vec3 c)
{
    c = clamp(c, 0.0, 1.0);
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

vec3 ramp(float t)
{
    vec3 stops[5];
    stops[0] = s0.xyz; stops[1] = s1.xyz; stops[2] = s2.xyz; stops[3] = s3.xyz; stops[4] = s4.xyz;
    float n = clamp(stopCount, 2.0, 5.0);
    float x = clamp(t, 0.0, 1.0) * (n - 1.0);
    int i = int(min(floor(x), n - 2.0));
    float f = x - float(i);
    f = f * f * (3.0 - 2.0 * f);
    vec3 lch = mix(stops[i], stops[i + 1], f);
    lch.x = mix(lch.x, min(lch.x, 0.7), lightMode);
    return toSrgb(oklabToLinear(vec3(lch.x, lch.y * cos(lch.z), lch.y * sin(lch.z))));
}

float hash(vec2 p)
{
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void main()
{
    vec2 p = qt_TexCoord0 * size;
    float y = mix(qt_TexCoord0.y, 1.0 - qt_TexCoord0.y, flip);   // 0 at the edge it hangs from
    float u = qt_TexCoord0.x;
    float X = (p.x - size.x * 0.5) / max(size.y, 1.0);
    float t = time;

    vec3 light = vec3(0.0);
    float cover = 0.0;
    for (int k = 0; k < 3; k++) {
        if (float(k) >= layers)
            break;
        float layer = float(k);
        float seed = layer * 13.7;
        float pace = t * (1.0 - layer * 0.18);
        float warp = snoise(vec2(X * 0.45 * waveScale + pace * 0.02 + seed, pace * 0.05 + seed));
        float wave = snoise(vec2(X * 0.75 * waveScale + warp * 0.35 - pace * 0.03 + seed, pace * 0.07 - seed)) * 0.72
                   + snoise(vec2(X * 1.6 * waveScale + warp * 0.5 + pace * 0.04 - seed, pace * 0.1 + seed * 0.5)) * 0.28;
        float edge = hem + layer * 0.07 + wave * 0.15 * amplitude;
        edge = mix(-0.25, edge, reveal);

        float soft = (0.04 + blend * 0.16) * (1.0 + layer * 0.9);
        float rise = edge - y;
        float low = -soft - glow * 0.14;
        float high = 0.26 + soft * 0.6;
        float body = pow(smootherstep(low, high, rise), 1.5 + glow * 0.6);
        float lobes = 0.86 + 0.14 * snoise(vec2(X * 0.9 * waveScale - pace * 0.025 + seed, y * 0.3 + pace * 0.04));
        float alpha = clamp(body * lobes * (layer < 0.5 ? 1.0 : 0.32 / layer), 0.0, 1.0);

        vec3 tint = ramp(u + 0.05 * sin(pace * 0.08 + layer * 2.3) + layer * 0.1 + max(rise, 0.0) * 0.05);
        light = 1.0 - (1.0 - light) * (1.0 - tint * alpha);
        cover = 1.0 - (1.0 - cover) * (1.0 - alpha);
    }

    float fade = smootherstep(0.0, 0.7, reveal);
    float strength = clamp(brightness, 0.0, 2.0);
    light *= fade * min(strength, 1.0);
    cover *= fade * min(strength, 1.0);
    light = 1.0 - pow(1.0 - light, vec3(max(strength, 1.0)));
    float dither = (hash(floor(p * dpr)) - 0.5) / 255.0;

    vec4 col;
    if (lightMode > 0.5) {
        vec3 tint = cover > 0.0001 ? light / cover : vec3(0.0);
        cover *= smootherstep(0.0, 0.25, cover);
        float a = cover * 0.7;
        col = vec4(tint * a + dither, a + dither);
    } else {
        col = vec4(light + dither, cover + dither);
    }
    fragColor = clamp(col, 0.0, 1.0) * qt_Opacity;
}
