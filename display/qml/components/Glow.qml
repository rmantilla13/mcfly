import QtQuick
import McFly

// Soft blue → coral → amber arch, painted once per resize. Used behind the
// assistant and in the photo frame's empty state.
Canvas {
    id: glow
    property real intensity: 1.0
    renderStrategy: Canvas.Cooperative
    // Repaint as the mood palette animates.
    readonly property var colors: [Theme.glowBlue, Theme.glowCoral, Theme.glowAmber, Theme.glowCream]
    onColorsChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        const w = width, h = height
        if (w <= 0 || h <= 0) return

        // Arch centred low and to the right, sweeping up from the bottom-left.
        // The widest pass spreads `reach` either side of the arc, and all of
        // it has to stay inside the canvas, or the top edge slices the glow
        // in a straight line. A radius from the width puts a landscape arc's
        // crest far above that, so there the arc is fitted instead: through
        // the bottom-left corner, cresting at `crest`.
        const band = h * 0.16
        const reach = band * (0.35 + 15 * 0.16) / 2
        const crest = reach + h * 0.12
        const cx = w * 0.62
        let cy = h * 1.18, r = Math.max(w, h) * 0.78
        if (cy - r < crest) {
            const rise = h - crest
            r = (rise + cx * cx / rise) / 2
            cy = crest + r
        }
        const grad = ctx.createLinearGradient(0, 0, w, 0)
        grad.addColorStop(0.00, glow.colors[0])
        grad.addColorStop(0.40, glow.colors[1])
        grad.addColorStop(0.72, glow.colors[2])
        grad.addColorStop(1.00, glow.colors[3])
        ctx.strokeStyle = grad
        ctx.lineCap = "round"

        // Many wide, faint passes approximate a blur without shader effects.
        for (let i = 0; i < 16; ++i) {
            ctx.globalAlpha = 0.06 * glow.intensity
            ctx.lineWidth = band * (0.35 + i * 0.16)
            ctx.beginPath()
            ctx.arc(cx, cy, r, Math.PI * 1.02, Math.PI * 1.98, false)
            ctx.stroke()
        }
        // Bright core of the band.
        ctx.globalAlpha = 0.55 * glow.intensity
        ctx.lineWidth = band * 0.55
        ctx.beginPath()
        ctx.arc(cx, cy, r, Math.PI * 1.02, Math.PI * 1.98, false)
        ctx.stroke()
    }
}
