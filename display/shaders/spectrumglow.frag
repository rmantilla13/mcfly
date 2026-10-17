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
// here depends on time. What depends only on x (each lobe's Gaussian
// across, the band's colour, the dome's profile, the bottom line's
// strength) comes from spectrumglow.vert, once a column of its mesh; what
// depends on the height is worked out here. The rows above the light aren't
// drawn at all (the vertex shader brings the top edge down to them). Bright
// overlaps roll off through a soft knee instead of clipping, and lit pixels
// get a level of triangular dither, since the ramps up from the dark host
// are long.
//
// Per pixel: 1 exp (2 where the brightest overlaps roll off), 2 sqrt
// (1 away from the corners), ~22 smoothstep on constant or precomputed
// edges, 2 hash.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 1) in vec4 vLobeA;    // lobes 0-3: alpha x Gaussian across, at this x
layout(location = 2) in vec4 vLobeB;    // lobes 4-6, and the dome's profile (bell)
layout(location = 3) in vec4 vBand;     // the band's colour, and the bottom line's strength
layout(location = 0) out vec4 fragColor;

// The same block as spectrumglow.vert, member for member.
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
    float cut;        // nothing is lit above this, logical px from the top (the vertex shader)
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
    vec4 r0;          // per lobe, 1 / its height (to the bottom edge): lobes 0-3
    vec4 r1;          // lobes 4-6, and 1 / (2 lobeBlur)
    vec4 r2;          // 1 / (2 bandBlur), 1 / (2 px), unused, unused
};

float hash12(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// smoothstep(e0, e0 + 1 / rcpWidth, x), with the division done beforehand.
float ramp(float e0, float rcpWidth, float x)
{
    float t = clamp((x - e0) * rcpWidth, 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

// One lobe at height y: a soft column from its top down past the bottom
// edge, rising smoothly to its brightest about three quarters down. `a` is
// its alpha and its Gaussian across at this x (the vertex shader), `rh`
// 1 / its height.
float lobe(float a, float top, float rh, float y)
{
    float d = y - top;
    float t = clamp(d * rh, 0.0, 1.0);
    float vert = smoothstep(0.0, 0.72, t) * (1.0 - 0.5 * smoothstep(0.72, 1.0, t));
    float topSoft = ramp(-lobeBlur, r1.w, d);   // smoothstep(top - lobeBlur, top + lobeBlur, y)
    return a * vert * topSoft;
}

void main()
{
    vec2 p = qt_TexCoord0 * size;
    float w = size.x;
    float h = size.y;
    float px = r2.z;
    float r = min(radius, min(w, h) * 0.5);

    // Everything stays inside the host's rounded shape.
    vec2 hs = 0.5 * size;
    vec2 q = abs(p - hs) - (hs - vec2(r));
    float dBox = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    float cover = clamp(0.5 - dBox * dpr, 0.0, 1.0);
    if (cover <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    float energy = dome.w;
    float bell = vLobeB.w;
    vec3 lobeColor = vBand.rgb;

    // The host's bottom edge at x, rising around the rounded corners.
    float dx = p.x < r ? r - p.x : (p.x > w - r ? p.x - (w - r) : 0.0);
    float floorY = h;
    if (dx > 0.0)
        floorY = h - r + sqrt(max(r * r - dx * dx, 0.0));

    // 1. Lobes: soft columns rising from the band, each following one voice band.
    vec3 col = k0.rgb * lobe(vLobeA.x, l0.y, r0.x, p.y);
    col += k1.rgb * lobe(vLobeA.y, l1.y, r0.y, p.y);
    col += k2.rgb * lobe(vLobeA.z, l2.y, r0.z, p.y);
    col += k3.rgb * lobe(vLobeA.w, l3.y, r0.w, p.y);
    col += k4.rgb * lobe(vLobeB.x, l4.y, r1.x, p.y);
    col += k5.rgb * lobe(vLobeB.y, l5.y, r1.y, p.y);
    col += k6.rgb * lobe(vLobeB.z, l6.y, r1.z, p.y);

    // 2. The band: strips of light along a curve that follows the bottom edge
    //    and bends up in the middle with the voice.
    float yc = floorY - 0.5 * bandWidth - dome.z * bell;
    float strength = 0.4 + 0.6 * energy;
    float rBlur = r2.x;
    // dome, pale: everything under the centerline
    float domeFade = 0.3 + 0.7 * bell;
    float domeFill = ramp(yc - bandBlur, rBlur, p.y);
    col += mix(lobeColor, vec3(1.0), 0.45) * (0.42 * strength * domeFade * domeFill);
    // mid
    float fadeMid = 0.1 + 0.9 * bell;
    float midLine = 1.0 - ramp(0.5 * bandWidth - bandBlur, rBlur, abs(p.y - (yc + 0.5 * bandWidth)));
    col += mix(lobeColor, vec3(1.0), 0.30) * (0.30 * strength * fadeMid * midLine);
    // core: the bright rim
    float fadeCore = 0.4 + 0.6 * bell;
    float coreLine = 1.0 - ramp(0.3 * bandWidth - bandBlur, rBlur, abs(p.y - yc));
    col += mix(lobeColor, vec3(1.0), 0.65) * (0.45 * strength * fadeCore * coreLine);
    // above: a halo
    float fadeAbove = 0.25 + 0.75 * bell;
    float aboveLine = 1.0 - ramp(0.5 * bandWidth - bandBlur, rBlur, abs(p.y - (yc - 0.6 * bandWidth)));
    col += mix(lobeColor, vec3(1.0), 0.20) * (0.30 * strength * fadeAbove * aboveLine);

    // 3. A thin line in the same colours right on the bottom edge.
    float lineAlpha = vBand.a;
    vec3 lineColor = mix(lobeColor, vec3(1.0), 0.2);
    float edgeD = abs(p.y - (floorY - 1.0));
    float glowLine = exp(-edgeD * edgeD / (2.0 * 2.5 * 2.5));
    float crisp = 1.0 - ramp(0.8 - px, r2.y, edgeD);
    col += lineColor * (lineAlpha * (0.6 * glowLine + crisp));

    // Soft knee: past 0.6 the brightest channel rolls off toward 1, and the
    // whole colour scales with it, so an overlap keeps its hue instead of
    // clipping channel by channel.
    col *= intensity;
    float m = max(col.r, max(col.g, col.b));
    if (m > 0.6)
        col *= (0.6 + 0.4 * (1.0 - exp(-(m - 0.6) / 0.4))) / m;

    // Triangular dither, one level, only where there is light: the host's
    // own dark stays clean.
    vec2 f = floor(p * dpr);
    col += (hash12(f) + hash12(f + 19.19) - 1.0) / 255.0 * step(1.0 / 255.0, m);

    // Additive: no alpha, so the host's own colour stays underneath.
    fragColor = vec4(max(col, 0.0) * cover * qt_Opacity, 0.0);
}
