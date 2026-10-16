#version 440
// Lens (qml/components/Lens.qml): the glass the controls are made of. A
// rounded rect of the control's fill, lit like glass: a rim lit from the top
// left, a sheen from the top, a caustic of the glow colours along the lower
// inside edge, and a soft shadow under it. An active control also shows the
// aura (the glow's colour fields, fixed to the window: Glass.qml) through
// itself, magnified toward its centre, pulled in at the bevel with a slight
// colour split there, its chroma lifted: so a pill gliding along the rail
// bends a different part of the aura as it goes.
//
// Nothing is sampled from the screen: the aura is worked out here from its
// four fields, so the glass needs no layer and no blur pass. A `wash` is the
// same aura, faint and flat, over a whole surface (the rail).
//
// The effect is the control plus `pad` all round, for the shadow. Output is
// premultiplied, layered bottom to top: shadow, fill, aura, lift, caustic,
// sheen, rim.
//
// Per pixel, inside: 4 exp per aura sample (3 samples at the bevel, 1
// within, none without aura), 1 exp for the rim, 1-2 for the caustic and
// shadow, and one OKLab conversion per sample.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;          // the effect, logical px: the control plus `pad` all round
    float pad;
    float radius;       // the control's corner radius
    float dpr;          // device pixel ratio: one physical px = 1/dpr logical px
    vec4 fill;          // the body (arrives premultiplied)
    float gather;       // how much of the aura shows, 0..1 (0: none, and none worked out)
    float saturation;   // the aura's chroma, times
    float magnify;      // the aura sampled this much closer to the centre (< 1 magnifies)
    float bend;         // logical px the aura is pulled inward at the bevel
    float dispersion;   // logical px between red and blue at the bevel
    float lift;         // white over the body, 0..1
    float caustic;      // the glow-coloured band inside the lower edge, 0..1
    float sheen;        // light from the top, 0..1
    float rim;          // the lit edge, 0..1
    vec4 shadow;        // y offset, blur (sigma), alpha, unused
    vec4 shadowColor;   // arrives premultiplied
    vec2 origin;        // the control's top-left in the window, logical px
    vec2 window;        // the window's size, logical px
    vec4 aura0;         // the aura's fields in OKLab (L, a, b) with their chroma:
    vec4 aura1;         //   three colours and a highlight (Glass.qml)
    vec4 aura2;
    vec4 aura3;
    vec2 auraAt0;       // where they sit, as shares of the window
    vec2 auraAt1;
    vec2 auraAt2;
    vec2 auraAt3;
    vec4 glow0;         // the glow in OKLab, for the caustic: blue, coral, amber
    vec4 glow1;
    vec4 glow2;
    float dark;         // 0 by day, 1 at night
};

const vec2 LIGHT = vec2(-0.5547, -0.8321);   // from the top left

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

float sdRoundRect(vec2 q, vec2 halfSize, float r)
{
    vec2 k = abs(q) - halfSize + vec2(r);
    return length(max(k, 0.0)) + min(max(k.x, k.y), 0.0) - r;
}

// The outward normal of the rounded rect, from its distance field.
vec2 normalAt(vec2 q, vec2 halfSize, float r)
{
    vec2 e = vec2(0.5, 0.0);
    vec2 g = vec2(sdRoundRect(q + e.xy, halfSize, r) - sdRoundRect(q - e.xy, halfSize, r),
                  sdRoundRect(q + e.yx, halfSize, r) - sdRoundRect(q - e.yx, halfSize, r));
    return g / max(length(g), 1e-5);
}

float blob(vec2 p, vec2 c, float inv)
{
    vec2 d = p - c;
    return exp(-dot(d, d) * inv);
}

// The aura at a point of the control: its colour fields averaged in OKLab,
// the chroma put back (an average of two hues is greyer than either), then
// lifted by `saturation`, then the highlight. Worked out in shares of the
// window, scaled to its shape (the square root of its area is the unit), so
// no value gets near the range of a mediump float the way squared window
// pixels would.
vec3 auraAt(vec2 local)
{
    vec2 shape = vec2(sqrt(window.x / window.y), sqrt(window.y / window.x));
    vec2 p = (origin + local) / window * shape;
    const float inv = 0.8 / 0.34;
    float w0 = blob(p, auraAt0 * shape, inv) + 0.02;
    float w1 = blob(p, auraAt1 * shape, inv);
    float w2 = blob(p, auraAt2 * shape, inv * 1.2);
    float ws = w0 + w1 + w2;
    vec3 lab = (aura0.xyz * w0 + aura1.xyz * w1 + aura2.xyz * w2) / ws;
    float chroma = (aura0.w * w0 + aura1.w * w1 + aura2.w * w2) / ws;
    lab.yz *= min(chroma / max(length(lab.yz), 1e-4), 2.5) * saturation;
    lab = mix(lab, aura3.xyz, 0.62 * blob(p, auraAt3 * shape, inv * 2.4));
    return oklabToSrgb(lab);
}

vec3 glowAlong(float u)
{
    u = clamp(u, 0.0, 1.0);
    return u < 0.55 ? mix(glow0.xyz, glow1.xyz, u / 0.55) : mix(glow1.xyz, glow2.xyz, (u - 0.55) / 0.45);
}

// Premultiplied `src` over `dst`.
vec4 over(vec4 src, vec4 dst) { return src + dst * (1.0 - src.a); }

void main()
{
    vec2 p = qt_TexCoord0 * size - vec2(pad);   // in the control, logical px
    vec2 box = max(size - 2.0 * vec2(pad), vec2(1.0));
    vec2 hs = 0.5 * box;
    vec2 q = p - hs;
    float px = 1.0 / dpr;
    float r = min(radius, min(hs.x, hs.y));
    float d = sdRoundRect(q, hs, r);
    float cover = clamp(0.5 - d / px, 0.0, 1.0);

    vec4 under = vec4(0.0);
    if (shadow.z > 0.0) {
        float sd = max(sdRoundRect(q - vec2(0.0, shadow.x), hs, r), 0.0);
        float a = shadow.z * exp(-sd * sd / (2.0 * shadow.y * shadow.y));
        vec3 sc = shadowColor.rgb / max(shadowColor.a, 0.001);
        under = vec4(sc * a, a);
    }
    if (cover <= 0.0) {
        fragColor = under * qt_Opacity;
        return;
    }

    float inset = max(-d, 0.0);
    vec2 n = normalAt(q, hs, r);
    vec2 uv = p / box;
    vec4 c = fill;

    if (gather > 0.0) {
        float bevel = min(min(hs.x, hs.y), 16.0);
        float t = 1.0 - clamp(inset / bevel, 0.0, 1.0);
        float b = t * t;
        vec2 s = hs + q * magnify - n * b * bend;
        vec3 aura;
        if (b * dispersion > 0.01) {
            vec2 dd = n * b * dispersion;
            aura = vec3(auraAt(s + dd).r, auraAt(s).g, auraAt(s - dd).b);
        } else {
            aura = auraAt(s);
        }
        c = over(vec4(aura * gather, gather), c);
    }
    c = over(vec4(vec3(lift), lift), c);

    float ca = caustic * max(n.y, 0.0) * exp(-(inset - 3.5) * (inset - 3.5) / 12.0);
    if (ca > 0.002) {
        vec3 g = glowAlong(uv.x);
        g = vec3(max(g.x, mix(0.86, 0.70, dark)), g.yz * 1.3);
        c = over(vec4(oklabToSrgb(g) * ca, ca), c);
    }

    float sh = sheen * 0.35 * pow(1.0 - clamp(uv.y, 0.0, 1.0), 3.0);
    c = over(vec4(vec3(sh), sh), c);

    float nl = dot(n, LIGHT);
    float band = exp(-(inset - 0.6) * (inset - 0.6) / 0.9);
    float ra = clamp(rim * band * (0.25 + 0.75 * max(nl, 0.0) + 0.4 * max(-nl, 0.0)), 0.0, 1.0);
    c = over(vec4(vec3(ra), ra), c);

    fragColor = (c * cover + under * (1.0 - c.a * cover)) * qt_Opacity;
}
