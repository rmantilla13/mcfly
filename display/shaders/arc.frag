#version 440
// Backdrop "Arc" (qml/components/Backdrop.qml): an aurora as seen from the
// ground. A band curves across the sky, bright along its lower edge and
// thinning upward, rays run up through it, brightness travels along it, and
// a fainter arc hangs behind. One pass, no textures. Built into a .qsb by
// qt_add_shaders.
//
// Shared with the other backdrops (ribbons, dawn, silk, pillars): the glow
// stops arrive in OKLCh with the hues unwrapped (Backdrop.qml) and ramp()
// picks its pair of stops by comparison, not a computed index, since the
// GLSL ES 1.00 this becomes on the Pi only promises constant indices. The
// light is laid on the canvas by an OKLab mix (`strength` says how much): a
// pastel wash on the warm canvas by day, a glow on the near-black one at
// night. Triangular dither, one step of the final picture. The simplex noise
// and the OKLab conversion are aurora.frag's.
//
// Four of the arc's five noise lookups depend on the column alone (X): the
// border's height, the rays' warp, the brightness along the arc, the second
// arc's border. arc.vert works them out once a column (column(), drawn by
// ScaledShader a strip per pixel column) and hands them on as vColumn, the
// same for every pixel of the column; here column() only reads it back. The
// console's sky works column() out per pixel, so scene() is the same text
// in both.
//
// Per pixel: 1 simplex noise, 1 OKLab -> sRGB, 2 hash; per column, 4 noise.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 1) in vec4 vColumn;   // column(X, time), from arc.vert
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

// The four stops blended in OKLCh, t 0..1 from the first to the last.
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

// What depends on the column alone, worked out by arc.vert.
vec4 column(float X, float t)
{
    return vColumn;
}

// The picture: its colour (OKLab) and how much of it there is, at uv (y up,
// 0 at the bottom edge).
void scene(vec2 uv, float aspect, out vec3 lab, out float a)
{
    float X = (uv.x - 0.5) * aspect;
    float Y = uv.y;
    float t = time;
    // The border, the warp, the brightness along, the second border.
    vec4 c = column(X, t);
    float yc = c.x;
    float d = Y - yc;
    // Bright at the border, a quick fall, then a long faint tail upward.
    float up = max(d, 0.0);
    float body = smoothstep(-0.03, 0.01, d) * (0.45 * exp(-up * 24.0) + 0.55 * exp(-up * 7.5));
    // Rays: a tall noise folded by a slow warp.
    float warp = c.y;
    float r = snoise(vec2(X * 14.0 + warp * 1.4, Y * 0.5 + t * 0.06));
    float rays = 0.5 + 0.5 * r;
    float along = c.z;
    a = body * (0.55 + 0.45 * rays) * along * 1.25;
    // A second, fainter arc behind.
    float yc2 = c.w;
    float d2 = Y - yc2;
    a += 0.3 * smoothstep(-0.05, 0.02, d2) * exp(-max(d2, 0.0) * 12.0) * (0.6 + 0.4 * r);
    // The first stop along the border, the others up through the rays.
    lab = ramp(clamp(up * 2.2, 0.0, 1.0) * 0.8 + 0.1 * warp + 0.1);
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
    // Triangular dither, one step of the final picture: the opacity comes
    // after it, so it is scaled up by as much.
    vec2 cell = floor(gl_FragCoord.xy);
    col += (hash(cell) + hash(cell + 17.13) - 1.0) / 255.0 / max(dim, 0.1);
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0) * qt_Opacity;
}
