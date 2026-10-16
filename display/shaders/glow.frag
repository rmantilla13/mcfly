#version 440
// Glow (qml/components/Glow.qml): a soft arch of the glow colours behind the
// assistant's empty state. A Gaussian band of light around an arc with a
// brighter core along it, the colours running left to right, blended in
// OKLab, and dithered so the long falloff can't band. One pass, no textures;
// it redraws only when its size, colours or opacity change.
//
// Per pixel: 1 exp, 3 pow, 1-3 length, 2 hash.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;        // item size, logical px
    float dpr;        // device pixel ratio
    vec2 center;      // the arc's centre, logical px (below the item)
    float arcRadius;  // logical px
    float band;       // the band's width, logical px: the core is half of it
    float intensity;  // 1 = as designed
    vec4 s0;          // colour stops in OKLab (L, a, b), left to right at 0, 0.40, 0.72 and 1
    vec4 s1;
    vec4 s2;
    vec4 s3;
};

float hash12(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
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
}

void main()
{
    vec2 p = qt_TexCoord0 * size;

    // Distance to the arc, which runs round the top of its circle from 1.02 pi
    // to 1.98 pi (y down), with round ends: past them, to the nearer end.
    vec2 d = p - center;
    float len = length(d);
    float dist = abs(len - arcRadius);
    if (d.y > -0.0627905 * len) {
        vec2 e = vec2(0.9980267, -0.0627905) * arcRadius;
        dist = min(length(d - vec2(-e.x, e.y)), length(d - e));
    }

    // A Gaussian glow (fitted to the 16 layered strokes it replaces, without
    // their steps) under a bright core with a soft edge.
    float x = dist / max(band, 1.0);
    float halo = 0.64 * exp(-x * x / 0.98);
    float core = 0.55 * (1.0 - smoothstep(0.215, 0.335, x));
    float a = clamp((core + halo * (1.0 - core)) * intensity, 0.0, 1.0);
    if (a < 0.5 / 255.0) {
        fragColor = vec4(0.0);
        return;
    }

    // The colour along x, stop to stop, in OKLab.
    float u = qt_TexCoord0.x;
    vec3 lab = mix(s0.xyz, s1.xyz, clamp(u / 0.40, 0.0, 1.0));
    if (u > 0.40)
        lab = mix(s1.xyz, s2.xyz, clamp((u - 0.40) / 0.32, 0.0, 1.0));
    if (u > 0.72)
        lab = mix(s2.xyz, s3.xyz, clamp((u - 0.72) / 0.28, 0.0, 1.0));
    vec3 col = oklabToSrgb(lab);

    // Premultiplied, with triangular dither (about one level) per physical pixel.
    vec2 f = floor(p * dpr);
    vec3 rgb = col * a + (hash12(f) + hash12(f + 19.19) - 1.0) / 255.0;
    fragColor = vec4(clamp(rgb, 0.0, a), a) * qt_Opacity;
}
