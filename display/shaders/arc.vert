#version 440
// Backdrop "Arc"'s vertex stage (arc.frag's): ScaledShader draws it as one
// strip per pixel column, each vertex given the u of its column's centre.
// What the arc works out from the column alone (column(): the border's
// height, the rays' warp, the brightness along the arc, the second arc's
// border, four of its five noise lookups) is worked out here once a column,
// at that centre, the same for all of the column's vertices, so every pixel
// of the column gets exactly it, as vColumn. column() is the console sky's
// (admin/components/sky-shaders.ts) line for line, and so is the noise.

layout(location = 0) in vec2 position;
layout(location = 1) in vec2 texCoord;
layout(location = 2) in float columnU;   // u of the column's centre

layout(location = 0) out vec2 qt_TexCoord0;
layout(location = 1) out vec4 vColumn;

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

// The border, the warp, the brightness along, the second border: what
// depends on the column alone.
vec4 column(float X, float t)
{
    // The arc's lower border: a curve, higher in the middle, bending slowly.
    float yc = 0.42 + 0.10 * cos(X * 0.9) + 0.07 * snoise(vec2(X * 0.6 + seed, t * 0.03));
    // The rays' slow warp.
    float warp = snoise(vec2(X * 1.2, t * 0.04 + seed));
    // Brightness travelling along the arc.
    float along = 0.4 + 0.6 * (0.5 + 0.5 * snoise(vec2(X * 1.1 - t * 0.05, 7.0 + seed)));
    // A second, fainter arc behind.
    float yc2 = yc + 0.24 + 0.05 * snoise(vec2(X * 0.5, t * 0.02 + 11.0));
    return vec4(yc, warp, along, yc2);
}

void main()
{
    qt_TexCoord0 = texCoord;
    float aspect = size.x / max(size.y, 1.0);
    vColumn = column((columnU - 0.5) * aspect, time);
    gl_Position = vec4(position, 0.0, 1.0);
}
