#version 440
// Backdrop "Silk" (qml/components/Backdrop.qml): two sheets of satin folding
// over each other. The folds catch a highlight where they turn toward us and
// shade where they turn away, and the glow runs across the weave. One pass,
// no textures, no noise: sines only. Built into a .qsb by qt_add_shaders.
//
// The stops, ramp(), the OKLab lay-on and the dither are as in arc.frag
// (the head of that file says how they work).
//
// Per pixel: 8 sin, 1 pow, 1 OKLab -> sRGB, 2 hash.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;         // item size, logical px
    float time;        // seconds x speed
    float strength;    // 0..1: how much of the light lands on the canvas
    float seed;        // picks a different sky
    float dim;         // the opacity applied after this shader (the dither is scaled to it)
    vec4 canvas;       // the canvas, OKLab (L, a, b)
    vec4 s0;           // the glow stops, OKLCh (L, C, hue in radians), hues unwrapped
    vec4 s1;
    vec4 s2;
    vec4 s3;
};

float hash(vec2 p)
{
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
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
}

void scene(vec2 uv, float aspect, out vec3 lab, out float a)
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
}

void main()
{
    vec2 uv = vec2(qt_TexCoord0.x, 1.0 - qt_TexCoord0.y);
    float aspect = size.x / max(size.y, 1.0);
    vec3 lab;
    float a;
    scene(uv, aspect, lab, a);
    a = clamp(a, 0.0, 1.0) * strength;
    vec3 col = oklabToSrgb(mix(canvas.xyz, lab, a));
    vec2 cell = floor(gl_FragCoord.xy);
    col += (hash(cell) + hash(cell + 17.13) - 1.0) / 255.0 / max(dim, 0.1);
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0) * qt_Opacity;
}
