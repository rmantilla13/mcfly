#version 440
// SpectrumGlow (qml/components/SpectrumGlow.qml): the voice glow from the
// Homestead app (itself a recreation of libraries.dev's voice-glow,
// "colorful"), drawn in one pass. Seven soft colour lobes rise from the
// bottom edge with the voice and flow slowly sideways; in front of them a
// layered band of light bends up into a wide dome; a thin spectrum line runs
// along the rounded bottom edge. While a reply is prepared everything gathers
// into one lit beam that travels side to side. Additive over a dark host.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;        // host size, logical px
    float radius;     // corner radius of the host, logical px
    float dpr;        // device pixel ratio
    float time;       // seconds
    float level;      // smoothed voice levels, 0..1
    float low;
    float mid;
    float high;
    float processing; // 0..1, eased
    float motion;     // 1 = animate, 0 = still (reduce motion)
    float kind;       // 0 = the bottom of a voice screen, 1 = an input-sized host
    float intensity;  // overall brightness, 1 = as designed
};

// The "colorful" palette, in the order the hue drifts: magenta, violet,
// blue, teal, green, amber, coral.
vec3 palette(float position)
{
    float p = mod(position, 7.0);
    int i = int(floor(p));
    float f = p - floor(p);
    vec3 c[8];
    c[0] = vec3(0.86, 0.28, 0.70); c[1] = vec3(0.56, 0.34, 0.90); c[2] = vec3(0.26, 0.50, 0.96);
    c[3] = vec3(0.14, 0.76, 0.76); c[4] = vec3(0.30, 0.76, 0.40); c[5] = vec3(0.96, 0.66, 0.24);
    c[6] = vec3(0.96, 0.38, 0.38); c[7] = c[0];
    vec3 a = c[0];
    vec3 b = c[1];
    if (i == 1) { a = c[1]; b = c[2]; }
    else if (i == 2) { a = c[2]; b = c[3]; }
    else if (i == 3) { a = c[3]; b = c[4]; }
    else if (i == 4) { a = c[4]; b = c[5]; }
    else if (i == 5) { a = c[5]; b = c[6]; }
    else if (i == 6) { a = c[6]; b = c[7]; }
    return mix(a, b, f);
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

    // Tuning, in units of `u`: the width for a voice screen, the height for an input.
    bool screen = kind < 0.5;
    float u = screen ? w : h;
    float restReach = screen ? 0.10 : 0.22, reach = screen ? 0.56 : 0.55;
    float restBend = screen ? 0.012 : 0.03, bend = screen ? 0.115 : 0.36;
    float spread = screen ? 0.5 : 0.36;
    float lobeWidth = screen ? 0.24 : 0.9, lobeBlur = screen ? 0.04 : 0.1;
    float bandWidth = u * (screen ? 0.04 : 0.07), bandBlur = u * (screen ? 0.016 : 0.03);

    float drift = time * 0.045 * motion;
    float process = processing;
    float beamX = w * (0.5 + 0.3 * sin(time * 1.3) * motion);
    float energy = max(level, 0.7 * process);
    float centerX = 0.5 * w + (beamX - 0.5 * w) * process;
    float halfWidth = w * (spread + (0.17 - spread) * process);

    // The host's bottom edge at x, rising around the rounded corners.
    float dx = p.x < r ? r - p.x : (p.x > w - r ? p.x - (w - r) : 0.0);
    float floorY = h - r + sqrt(max(r * r - dx * dx, 0.0));

    // The dome's profile at this x: 1 in the middle, falling off toward the corners.
    float bd = (p.x - centerX) / (halfWidth * 0.47);
    float bell = 1.0 / (1.0 + bd * bd);

    float bands[7];
    bands[0] = low; bands[1] = mid; bands[2] = high; bands[3] = mid; bands[4] = low; bands[5] = high; bands[6] = mid;

    vec3 col = vec3(0.0);
    // The lobes' colour at this x, for the band and the edge line.
    vec3 lobeSum = vec3(0.0);
    float lobeTotal = 1e-6;

    // 1. Lobes: soft columns rising from the band, each following one voice band.
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        float flow = fract(fi / 7.0 + time * 0.05 * motion);
        float s = (flow * 2.0 - 1.0) * 1.2;
        float restX = 0.5 * w + s * 0.5 * w;
        float edgeFade = clamp((1.2 - abs(s)) / 0.35, 0.0, 1.0);
        float band = bands[i];
        float breath = 0.025 * sin(time * 0.9 + fi * 2.1) * motion;
        float rd = (restX - centerX) / (halfWidth * 0.47);
        float restBell = 1.0 / (1.0 + rd * rd);
        float voiceHeight = u * (restReach + breath + reach * band) * (0.55 + 0.45 * restBell);
        float x = restX + (beamX + (fi - 3.0) * w * 0.03 - restX) * process;
        float height = voiceHeight + (u * reach * 0.8 - voiceHeight) * process;
        float width = u * lobeWidth * (1.0 - 0.3 * process);
        float alpha = ((0.16 + 0.55 * max(band, level * 0.6)) * edgeFade * (0.3 + 0.7 * restBell)) * (1.0 - process) + 0.45 * process;
        float weight = edgeFade + (1.0 - edgeFade) * process;
        vec3 color = palette(fi + drift);

        // Soft column: a blurred rounded rectangle from (h - height) down past the edge.
        float blur = u * lobeBlur;
        float hx = abs(p.x - x);
        float horiz = 1.0 - smoothstep(0.5 * width - blur, 0.5 * width + blur, hx);
        float top = h - height;
        float t = clamp((p.y - top) / max(height, 1.0), 0.0, 1.0);
        float vert = t < 0.72 ? t / 0.72 : mix(1.0, 0.5, (t - 0.72) / 0.28);
        float topSoft = smoothstep(top - blur, top + blur, p.y);
        col += color * (alpha * horiz * vert * topSoft);

        float cd = (p.x - x) / (w * 0.16);
        float cw = exp(-cd * cd) * weight + 1e-6;
        lobeSum += color * cw;
        lobeTotal += cw;
    }
    vec3 lobeColor = lobeSum / lobeTotal;

    // 2. The band: strips of light along a curve that follows the bottom edge
    //    and bends up in the middle with the voice.
    float crest = u * (restBend + bend * energy) * (1.0 - process) + u * bend * 0.85 * process;
    float yc = floorY - 0.5 * bandWidth - crest * bell;
    float strength = 0.4 + 0.6 * energy;
    // dome, pale: everything under the centerline
    float domeFade = 0.3 + 0.7 * bell;
    float dome = smoothstep(yc - bandBlur, yc + bandBlur, p.y);
    col += mix(lobeColor, vec3(1.0), 0.45) * (0.42 * strength * domeFade * dome);
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

    // Additive: no alpha, so the host's own colour stays underneath.
    fragColor = vec4(clamp(col * intensity, 0.0, 1.2) * cover * qt_Opacity, 0.0);
}
