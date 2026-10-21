import QtQuick

// The McFly mark: the flux capacitor's Y, three tubes in blue, coral and
// amber running in to a white core, on a dark tile. The colours are fixed
// (the day glow), so the logo doesn't follow the time of day. The same
// numbers draw the apps' and the console's mark, the iPhone's launch mark
// and app icon (apple/scripts), and, with its window and lights, the boot
// clip (display/deploy/boot/make-boot-video.py).
Item {
    id: mark
    implicitWidth: 52
    implicitHeight: implicitWidth
    property real radius: width * 0.26

    Canvas {
        id: canvas
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const c = getContext("2d")
            const s = Math.min(width, height)
            c.reset()
            if (s <= 0)
                return
            c.save()
            c.beginPath()
            c.roundedRect(0, 0, s, s, mark.radius, mark.radius)
            c.clip()
            const tile = c.createLinearGradient(0, 0, 0, s)
            tile.addColorStop(0, "#30323A")
            tile.addColorStop(1, "#121317")
            c.fillStyle = tile
            c.fillRect(0, 0, s, s)
            // A Y, 120 degrees apart: up-left, up-right, down.
            const arms = [[-0.8660254, -0.5, "#5B7CF5", "#B5C4FA"],
                          [0.8660254, -0.5, "#F07F5A", "#F8C5B5"],
                          [0, 1, "#F6B94A", "#FBE0AE"]]
            const cx = s / 2, cy = s * 0.53
            c.lineCap = "round"
            c.lineWidth = s * 0.12
            for (const a of arms) {
                const x0 = cx + a[0] * s * 0.14, y0 = cy + a[1] * s * 0.14
                const x1 = cx + a[0] * s * 0.36, y1 = cy + a[1] * s * 0.36
                const tube = c.createLinearGradient(x1, y1, x0, y0)
                tube.addColorStop(0, a[2])
                tube.addColorStop(1, a[3])
                c.shadowColor = a[2]
                c.shadowBlur = s * 0.12
                c.strokeStyle = tube
                c.beginPath()
                c.moveTo(x0, y0)
                c.lineTo(x1, y1)
                c.stroke()
            }
            c.shadowColor = "#FFFFFF"
            c.shadowBlur = s * 0.16
            c.fillStyle = "#FFFFFF"
            c.beginPath()
            c.arc(cx, cy, s * 0.075, 0, 2 * Math.PI)
            c.fill()
            c.restore()
        }
    }
}
