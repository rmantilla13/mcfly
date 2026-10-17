#version 440
// SpectrumGlow's vertices (qml/components/SpectrumGlow.qml, with
// spectrumglow.frag). The glow is drawn on a mesh of thin columns, one row
// tall, and everything in it that depends only on how far across a pixel is
// gets worked out here, once a column, and slides across to the pixels in
// between: how bright each lobe is at this x (its Gaussian across), the
// band's colour (the lobes' colours by nearness), the dome's profile and
// the bottom line's strength. All of them are wide and soft (the narrowest,
// a lobe or the dome while it gathers into the beam, is ~60 px across), so a
// column 2 px wide follows each to a small fraction of a level. What
// depends on the height stays per pixel, in the fragment shader.
//
// The mesh's top edge comes down to `cut`, the highest point anything in
// the glow is lit (SpectrumGlow.qml works it out): above it every pixel
// would add nothing to the dark host, so it is not drawn at all.
//
// Per vertex: 14 exp, 1 sin.

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;

layout(location = 0) out vec2 qt_TexCoord0;
layout(location = 1) out vec4 vLobeA;    // lobes 0-3: alpha x Gaussian across, at this x
layout(location = 2) out vec4 vLobeB;    // lobes 4-6, and the dome's profile (bell)
layout(location = 3) out vec4 vBand;     // the band's colour, and the bottom line's strength

// The same block as spectrumglow.frag, member for member.
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float radius;
    float dpr;
    float intensity;
    float bandWidth;
    float bandBlur;
    float lobeBlur;
    float cut;
    vec4 dome;
    vec4 l0;
    vec4 l1;
    vec4 l2;
    vec4 l3;
    vec4 l4;
    vec4 l5;
    vec4 l6;
    vec4 k0;
    vec4 k1;
    vec4 k2;
    vec4 k3;
    vec4 k4;
    vec4 k5;
    vec4 k6;
    vec4 r0;
    vec4 r1;
    vec4 r2;
};

out gl_PerVertex { vec4 gl_Position; };

// One lobe at x: its light across (alpha x Gaussian), and its colour, by
// nearness, into the band's.
float lobe(vec4 l, vec4 k, float x, float spread, inout vec3 sum, inout float total)
{
    float hx = x - l.x;
    float cw = exp(-hx * hx * spread) * k.w + 1e-6;
    sum += k.rgb * cw;
    total += cw;
    return l.w * exp(-hx * hx * l.z);
}

void main()
{
    vec4 v = qt_Vertex;
    vec2 tc = qt_MultiTexCoord0;
    // The top edge, down to where the light starts.
    if (tc.y < 0.5) {
        v.y = clamp(cut, 0.0, size.y);
        tc.y = v.y / max(size.y, 1.0);
    }
    qt_TexCoord0 = tc;
    gl_Position = qt_Matrix * v;

    float x = tc.x * size.x;
    float w = size.x;
    vec3 sum = vec3(0.0);
    float total = 1e-6;
    float spread = 1.0 / (0.0256 * w * w);   // how far a lobe colours the band: (0.16 w)^-2
    vLobeA.x = lobe(l0, k0, x, spread, sum, total);
    vLobeA.y = lobe(l1, k1, x, spread, sum, total);
    vLobeA.z = lobe(l2, k2, x, spread, sum, total);
    vLobeA.w = lobe(l3, k3, x, spread, sum, total);
    vLobeB.x = lobe(l4, k4, x, spread, sum, total);
    vLobeB.y = lobe(l5, k5, x, spread, sum, total);
    vLobeB.z = lobe(l6, k6, x, spread, sum, total);
    // The dome's profile: 1 in the middle, falling off toward the corners.
    float bd = (x - dome.x) / dome.y;
    vLobeB.w = 1.0 / (1.0 + bd * bd);
    vBand.rgb = sum / total;
    // The bottom line, brightest in the middle.
    vBand.a = (0.25 + 0.45 * dome.w) * (0.35 + 0.65 * sin(tc.x * 3.14159265));
}
