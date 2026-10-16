#version 440
// GradientTile (qml/components/GradientTile.qml), "Poster glow": a luminous
// pastel mesh gradient with one or two frosted-glass rings drifting across it,
// static film grain, and an antialiased rounded-corner mask. One pass, no
// textures, no loops. Built into a .qsb by qt_add_shaders.
//
// Where the rings and colour fields are comes in as points: GradientTile.qml
// works out their drift once per update, so nothing here depends on time.
// The colour fields blend in OKLCh (lightness, chroma, hue), so two hues meet
// through the hues between them at full strength instead of greying out.
//
// `soft` blurs the rings into the gradient: the lens edge, the frost, the rim
// and its halo fade over a fraction of the ring's radius instead of over a
// pixel, so the blur reads the same on every panel. All of it is analytic:
// no blur pass, nothing sampled twice. The tile's own corners stay 1 px sharp.
//
// Per pixel: 8 exp, 1 sin + 1 cos, 3 pow, ~5 smoothstep/clamp, 4 length, 2 hash.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;        // tile size, logical px
    float radius;     // corner radius, logical px
    float dpr;        // device pixel ratio: one physical px = 1/dpr logical px
    float rings;      // 0, 1 or 2 glass rings
    float r1;         // ring 1's radius, logical px (ring 2 is 0.72 of it)
    float glass;      // glass strength: rims x glass, frost x glass^2 (dimmed at night)
    float grain;      // film-grain amplitude (0.035: most pixels within +-4/255)
    float soft;       // ring softness: 0 = crisp glass edges, 1 = blurred into the gradient
    vec2 r1c;         // ring centres, logical px
    vec2 r2c;
    vec2 b0;          // colour-field centres, logical px: main hue,
    vec2 b1;          //   analogous one way,
    vec2 b2;          //   analogous the other way,
    vec2 b3;          //   the soft highlight
    vec4 lch0;        // the three colour fields in OKLCh: L, C, hue in radians,
    vec4 lch1;        //   unwrapped from one to the next so a blend goes the short way
    vec4 lch2;
    vec4 tint;        // field 2 in OKLab, tinting where the rings overlap
    vec4 hilite;      // the soft highlight in OKLab
    vec4 rimColor;    // rim + frost colour, alpha = rim strength (arrives premultiplied)
};

float hash12(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float blob(vec2 p, vec2 c, float inv)
{
    vec2 d = p - c;
    return exp(-dot(d, d) * inv);
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
    float px = 1.0 / dpr;

    // Rounded-rect coverage from a signed distance: 1 physical px of AA.
    vec2 hs = 0.5 * size;
    vec2 q = abs(p - hs) - (hs - vec2(radius));
    float dBox = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    float cover = clamp(0.5 - dBox / px, 0.0, 1.0);
    if (cover <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    // ---- Glass rings (geometry first: they bend the gradient behind them).
    float R1 = r1;
    float R2 = 0.72 * R1;

    vec2 d1 = p - r1c;
    vec2 d2 = p - r2c;
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
    // shifted, so the ring reads as glass; overlaps bend twice. Soft rings
    // bend less, and the bend eases in across the edge instead of jumping.
    float lens = 1.0 - 0.35 * soft;
    vec2 ps = p - lens * in1 * (0.14 * d1 + vec2(0.07, -0.05) * R1)
                - lens * in2 * (0.14 * d2 + vec2(-0.05, 0.07) * R2);

    // ---- Mesh gradient: three drifting colour fields + a soft highlight,
    // blended in OKLCh and OKLab, then into sRGB once.
    float S = sqrt(size.x * size.y);
    float inv = 1.0 / (0.34 * S * S);
    float w0 = blob(ps, b0, inv) + 0.02;
    float w1 = blob(ps, b1, inv);
    float w2 = blob(ps, b2, inv * 1.2);
    vec3 lch = (lch0.xyz * w0 + lch1.xyz * w1 + lch2.xyz * w2) / (w0 + w1 + w2);
    vec3 lab = vec3(lch.x, lch.y * cos(lch.z), lch.y * sin(lch.z));
    lab = mix(lab, hilite.xyz, 0.62 * blob(ps, b3, inv * 2.4));
    lab = mix(lab, tint.xyz, 0.30 * in1 * in2);   // the rings' overlap
    vec3 col = oklabToSrgb(lab);

    // Faint top sheen, like light on a glass sheet.
    col += glass * 0.035 * (1.0 - qt_TexCoord0.y);

    // Qt hands colour uniforms over premultiplied; the palette is opaque, the rim is not.
    vec3 rim = rimColor.rgb / max(rimColor.a, 0.001);

    // ---- Frost: a faint fill that brightens toward the rim (less when soft,
    // or the bright band would still end in a line).
    float e1 = min(l1 / max(R1, 1.0), 1.0);
    float e2 = min(l2 / max(R2, 1.0), 1.0);
    float toRim = 0.16 * (1.0 - 0.55 * soft);
    float frost = in1 * (0.07 + toRim * e1 * e1 * e1) + in2 * (0.07 + toRim * e2 * e2 * e2);
    col = mix(col, rim, glass * glass * frost);

    // ---- Rims: a ridge across the ring's edge, lit from the top-left, with a
    // halo. Crisp: about a pixel wide. Soft: 3% of the radius wide (the halo
    // 10%), and fainter, so a wider ridge isn't a brighter one.
    vec2 L = vec2(-0.6, -0.8);
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
    col = mix(col, rim, glass * rimColor.a * clamp(lines, 0.0, 1.0));

    // ---- Film grain: static, one value per physical pixel (never animated, so
    // it can't shimmer and costs no frames), from two hashes so it clusters
    // around zero like real grain instead of spreading evenly.
    vec2 gp = floor(p * dpr);
    col += (hash12(gp) + hash12(gp.yx * 1.618 + 71.3) - 1.0) * grain;

    fragColor = vec4(clamp(col, 0.0, 1.0) * cover, cover) * qt_Opacity;
}
