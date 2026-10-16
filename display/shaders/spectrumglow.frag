#version 440
// SpectrumGlow (qml/components/SpectrumGlow.qml): the voice glow from the
// Homestead app (itself a recreation of libraries.dev's voice-glow,
// "colorful"), drawn in one pass. Seven soft colour lobes rise from the
// bottom edge with the voice and flow slowly sideways; in front of them a
// layered band of light bends up into a wide dome; a thin spectrum line runs
// along the rounded bottom edge. While a reply is prepared everything gathers
// into one lit beam that travels side to side. Additive over a dark host.
//
// Where the lobes are, their sizes, strengths and colours come in as
// uniforms (SpectrumGlow.qml works them out once per update), so nothing
// here depends on time. Bright overlaps roll off through a soft knee instead
// of clipping, and lit pixels get a level of triangular dither, since the
// ramps up from the dark host are long.
//
// Per pixel: 16 exp, 1 sin, 1 sqrt, ~26 smoothstep, 2 hash.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;        // host size, logical px
    float radius;     // corner radius of the host, logical px
    float dpr;        // device pixel ratio
    float intensity;  // overall brightness, 1 = as designed
    float bandWidth;  // the band's strips, logical px
    float bandBlur;
    float lobeBlur;   // the soft top of a lobe, logical px
    vec4 dome;        // centre x, half width (of the bell), crest height (logical px), energy 0..1
    vec4 l0;          // per lobe: x, top (logical px), 1/(2 sigma^2) of its width, alpha
    vec4 l1;
    vec4 l2;
    vec4 l3;
    vec4 l4;
    vec4 l5;
    vec4 l6;
    vec4 k0;          // per lobe: colour (sRGB), weight in the band's colour
    vec4 k1;
    vec4 k2;
    vec4 k3;
    vec4 k4;
    vec4 k5;
    vec4 k6;
};

float hash12(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// One lobe: a soft column from its top down past the bottom edge, Gaussian
// across, rising smoothly to its brightest about three quarters down. Adds
// its light to `col` and its colour, by nearness, to the band's colour.
void lobe(vec4 l, vec4 k, vec2 p, float spread, inout vec3 col, inout vec3 sum, inout float total)
{
    float hx = p.x - l.x;
    float horiz = exp(-hx * hx * l.z);
    float t = clamp((p.y - l.y) / max(size.y - l.y, 1.0), 0.0, 1.0);
    float vert = smoothstep(0.0, 0.72, t) * (1.0 - 0.5 * smoothstep(0.72, 1.0, t));
    float topSoft = smoothstep(l.y - lobeBlur, l.y + lobeBlur, p.y);
    col += k.rgb * (l.w * horiz * vert * topSoft);

    float cw = exp(-hx * hx * spread) * k.w + 1e-6;
    sum += k.rgb * cw;
    total += cw;
}

void main()
{
    vec2 p = qt_TexCoord0 * size;
    float w = size.x;
    float h = size.y;
    float px = 1.0 / dpr;
    float r = min(radius, min(w, h) * 0.5);

    // Everything stays inside the host's rounded shape.
    vec2 hs = 0.5 * size;
    vec2 q = abs(p - hs) - (hs - vec2(r));
    float dBox = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    float cover = clamp(0.5 - dBox / px, 0.0, 1.0);
    if (cover <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    float energy = dome.w;

    // The host's bottom edge at x, rising around the rounded corners.
    float dx = p.x < r ? r - p.x : (p.x > w - r ? p.x - (w - r) : 0.0);
    float floorY = h - r + sqrt(max(r * r - dx * dx, 0.0));

    // The dome's profile at this x: 1 in the middle, falling off toward the corners.
    float bd = (p.x - dome.x) / dome.y;
    float bell = 1.0 / (1.0 + bd * bd);

    // 1. Lobes: soft columns rising from the band, each following one voice band.
    vec3 col = vec3(0.0);
    vec3 lobeSum = vec3(0.0);
    float lobeTotal = 1e-6;
    float spread = 1.0 / (0.0256 * w * w);   // how far a lobe colours the band: (0.16 w)^-2
    lobe(l0, k0, p, spread, col, lobeSum, lobeTotal);
    lobe(l1, k1, p, spread, col, lobeSum, lobeTotal);
    lobe(l2, k2, p, spread, col, lobeSum, lobeTotal);
    lobe(l3, k3, p, spread, col, lobeSum, lobeTotal);
    lobe(l4, k4, p, spread, col, lobeSum, lobeTotal);
    lobe(l5, k5, p, spread, col, lobeSum, lobeTotal);
    lobe(l6, k6, p, spread, col, lobeSum, lobeTotal);
    vec3 lobeColor = lobeSum / lobeTotal;

    // 2. The band: strips of light along a curve that follows the bottom edge
    //    and bends up in the middle with the voice.
    float yc = floorY - 0.5 * bandWidth - dome.z * bell;
    float strength = 0.4 + 0.6 * energy;
    // dome, pale: everything under the centerline
    float domeFade = 0.3 + 0.7 * bell;
    float domeFill = smoothstep(yc - bandBlur, yc + bandBlur, p.y);
    col += mix(lobeColor, vec3(1.0), 0.45) * (0.42 * strength * domeFade * domeFill);
    // mid
    float fadeMid = 0.1 + 0.9 * bell;
    float midLine = 1.0 - smoothstep(0.5 * bandWidth - bandBlur, 0.5 * bandWidth + bandBlur, abs(p.y - (yc + 0.5 * bandWidth)));
    col += mix(lobeColor, vec3(1.0), 0.30) * (0.30 * strength * fadeMid * midLine);
    // core: the bright rim
    float fadeCore = 0.4 + 0.6 * bell;
    float coreLine = 1.0 - smoothstep(0.3 * bandWidth - bandBlur, 0.3 * bandWidth + bandBlur, abs(p.y - yc));
    col += mix(lobeColor, vec3(1.0), 0.65) * (0.45 * strength * fadeCore * coreLine);
    // above: a halo
    float fadeAbove = 0.25 + 0.75 * bell;
    float aboveLine = 1.0 - smoothstep(0.5 * bandWidth - bandBlur, 0.5 * bandWidth + bandBlur, abs(p.y - (yc - 0.6 * bandWidth)));
    col += mix(lobeColor, vec3(1.0), 0.20) * (0.30 * strength * fadeAbove * aboveLine);

    // 3. A thin line in the same colours right on the bottom edge.
    float lineAlpha = (0.25 + 0.45 * energy) * (0.35 + 0.65 * sin(qt_TexCoord0.x * 3.14159265));
    vec3 lineColor = mix(lobeColor, vec3(1.0), 0.2);
    float edgeD = abs(p.y - (floorY - 1.0));
    float glowLine = exp(-edgeD * edgeD / (2.0 * 2.5 * 2.5));
    float crisp = 1.0 - smoothstep(0.8 - px, 0.8 + px, edgeD);
    col += lineColor * (lineAlpha * (0.6 * glowLine + crisp));

    // Soft knee: past 0.6 the brightest channel rolls off toward 1, and the
    // whole colour scales with it, so an overlap keeps its hue instead of
    // clipping channel by channel.
    col *= intensity;
    float m = max(col.r, max(col.g, col.b));
    float knee = m > 0.6 ? (0.6 + 0.4 * (1.0 - exp(-(m - 0.6) / 0.4))) / m : 1.0;
    col *= knee;

    // Triangular dither, one level, only where there is light: the host's
    // own dark stays clean.
    vec2 f = floor(p * dpr);
    col += (hash12(f) + hash12(f + 19.19) - 1.0) / 255.0 * step(1.0 / 255.0, m);

    // Additive: no alpha, so the host's own colour stays underneath.
    fragColor = vec4(max(col, 0.0) * cover * qt_Opacity, 0.0);
}
