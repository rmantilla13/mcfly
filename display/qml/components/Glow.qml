import QtQuick
import McFly

// Soft blue → coral → amber arch behind the assistant's empty state.
//
// Drawn by shaders/glow.frag in one pass: a Gaussian band of light around
// the arc with a brighter core, the colours blended in OKLab and dithered.
// It costs nothing while it stands still and only re-shades on the GPU as
// the mood palette fades. Where shaders don't run (software rendering) the
// layered Canvas strokes it replaced stand in.
Item {
    id: glow
    property real intensity: 1.0
    readonly property var colors: [Theme.glowBlue, Theme.glowCoral, Theme.glowAmber, Theme.glowCream]

    readonly property bool fallback: GraphicsInfo.api === GraphicsInfo.Software
                                     || fx.status === ShaderEffect.Error

    // Arch centred low and to the right, sweeping up from the bottom-left.
    // The glow spreads `reach` either side of the arc and has to fade out
    // inside the item, or the top edge slices it in a straight line. A
    // radius from the width puts a landscape arc's crest far above that, so
    // there the arc is fitted instead: through the bottom-left corner,
    // cresting at `crest`.
    readonly property real _band: height * 0.16
    readonly property var _arc: {
        const w = width, h = height, band = _band
        if (w <= 0 || h <= 0)
            return { cx: 0, cy: 0, r: 0 }
        const reach = band * (0.35 + 15 * 0.16) / 2
        const crest = reach + h * 0.12
        const cx = w * 0.62
        let cy = h * 1.18, r = Math.max(w, h) * 0.78
        if (cy - r < crest) {
            const rise = h - crest
            r = (rise + cx * cx / rise) / 2
            cy = crest + r
        }
        return { cx: cx, cy: cy, r: r }
    }
    function _lab(c) { const v = Theme.oklab(c); return Qt.vector4d(v[0], v[1], v[2], 0) }

    ShaderEffect {
        id: fx
        anchors.fill: parent
        visible: !glow.fallback
        // Uniforms (names match shaders/glow.frag).
        readonly property size size: Qt.size(width, height)
        readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
        readonly property vector2d center: Qt.vector2d(glow._arc.cx, glow._arc.cy)
        readonly property real arcRadius: glow._arc.r
        readonly property real band: glow._band
        readonly property real intensity: glow.intensity
        readonly property vector4d s0: glow._lab(glow.colors[0])
        readonly property vector4d s1: glow._lab(glow.colors[1])
        readonly property vector4d s2: glow._lab(glow.colors[2])
        readonly property vector4d s3: glow._lab(glow.colors[3])
        fragmentShader: "qrc:/McFly/shaders/glow.frag.qsb"
    }

    // No shaders: many wide, faint strokes approximate the blur. Painted on
    // the CPU, so a palette fade repaints once it has settled, not per step.
    Loader {
        anchors.fill: parent
        active: glow.fallback
        sourceComponent: Canvas {
            id: canvas
            renderStrategy: Canvas.Cooperative
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Connections {
                target: glow
                function onColorsChanged() { settle.restart() }
            }
            Timer { id: settle; interval: 250; onTriggered: canvas.requestPaint() }

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const band = glow._band, arc = glow._arc
                if (width <= 0 || height <= 0) return
                const grad = ctx.createLinearGradient(0, 0, width, 0)
                grad.addColorStop(0.00, glow.colors[0])
                grad.addColorStop(0.40, glow.colors[1])
                grad.addColorStop(0.72, glow.colors[2])
                grad.addColorStop(1.00, glow.colors[3])
                ctx.strokeStyle = grad
                ctx.lineCap = "round"
                for (let i = 0; i < 16; ++i) {
                    ctx.globalAlpha = 0.06 * glow.intensity
                    ctx.lineWidth = band * (0.35 + i * 0.16)
                    ctx.beginPath()
                    ctx.arc(arc.cx, arc.cy, arc.r, Math.PI * 1.02, Math.PI * 1.98, false)
                    ctx.stroke()
                }
                // Bright core of the band.
                ctx.globalAlpha = 0.55 * glow.intensity
                ctx.lineWidth = band * 0.55
                ctx.beginPath()
                ctx.arc(arc.cx, arc.cy, arc.r, Math.PI * 1.02, Math.PI * 1.98, false)
                ctx.stroke()
            }
        }
    }
}
