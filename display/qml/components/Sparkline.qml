import QtQuick
import QtQuick.Shapes
import McFly
import McFly.Core

// A price history as a thin line with a soft fill under it. The points are
// plain numbers (oldest first); the line is scaled to fill the item with a
// little headroom. Up days are green, down days coral.
//
// `progress` draws it on from the left (a screen's reveal: a clip, so the
// path isn't rebuilt), the newest point landing last. `pulse` (a value that
// just moved) sends three slow rings out from that point, then rests: a live
// feed moves all day, and a ring that never stops is a redraw that never does.
Item {
    id: spark
    property var points: []
    property color color: Theme.success
    property real lineWidth: 3
    property real progress: 1
    property bool pulse: false
    property bool running: true

    readonly property int count: points ? points.length : 0
    readonly property real low: count > 0 ? Math.min.apply(null, points) : 0
    readonly property real high: count > 0 ? Math.max.apply(null, points) : 1
    readonly property real span: high - low > 0 ? high - low : (high !== 0 ? Math.abs(high) * 0.02 : 1)

    function xAt(i) { return count > 1 ? i * width / (count - 1) : width / 2 }
    function yAt(v) { return height - 4 - (v - low) / span * (height - 8) }

    // The path is rebuilt only when the points change, not every frame. From
    // the points themselves: in onPointsChanged, count, low and span may not
    // have caught up yet (a board tile kept across a sync or a board change
    // gets new points of another length).
    property string linePath: ""
    property string fillPath: ""
    function rebuild() {
        const pts = points || []
        const n = pts.length
        if (n < 2 || width <= 0 || height <= 0) {
            linePath = ""
            fillPath = ""
            return
        }
        const lo = Math.min.apply(null, pts), hi = Math.max.apply(null, pts)
        const sp = hi - lo > 0 ? hi - lo : (hi !== 0 ? Math.abs(hi) * 0.02 : 1)
        const x = i => i * width / (n - 1)
        const y = v => height - 4 - (v - lo) / sp * (height - 8)
        var d = "M " + x(0) + " " + y(pts[0])
        for (var i = 1; i < n; i++)
            d += " L " + x(i) + " " + y(pts[i])
        linePath = d
        fillPath = d + " L " + width + " " + height + " L 0 " + height + " Z"
    }
    onPointsChanged: rebuild()
    onWidthChanged: rebuild()
    onHeightChanged: rebuild()
    Component.onCompleted: rebuild()

    // Drawn in software (a fallback, and offscreen pictures), a clipped path
    // that moves every frame can smear past its clip: it is simply there.
    readonly property real _drawn: GraphicsInfo.api === GraphicsInfo.Software ? 1 : Math.max(0, Math.min(1, progress))
    Item {
        width: Math.round(spark.width * spark._drawn)
        height: spark.height
        clip: spark._drawn < 1
        Shape {
            width: spark.width
            height: spark.height
            visible: spark.fillPath !== ""
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"
                fillGradient: LinearGradient {
                    x1: 0; y1: 0; x2: 0; y2: spark.height
                    GradientStop { position: 0; color: Qt.rgba(spark.color.r, spark.color.g, spark.color.b, 0.28) }
                    GradientStop { position: 1; color: Qt.rgba(spark.color.r, spark.color.g, spark.color.b, 0.0) }
                }
                PathSvg { path: spark.fillPath }
            }
            ShapePath {
                strokeColor: spark.color
                strokeWidth: spark.lineWidth
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: spark.linePath }
            }
        }
    }
    // The newest point, once the line has reached it.
    Rectangle {
        id: last
        visible: spark.count > 1
        x: spark.width - width / 2
        y: spark.count > 0 ? spark.yAt(spark.points[spark.count - 1]) - height / 2 : 0
        width: spark.lineWidth * 2.4; height: width; radius: width / 2
        color: spark.color
        opacity: Math.max(0, Math.min(1, (spark._drawn - 0.9) * 10))
        Rectangle {
            id: ring
            anchors.centerIn: parent
            width: parent.width; height: width; radius: width / 2
            color: "transparent"
            border.width: Math.max(1.5, spark.lineWidth * 0.6)
            border.color: spark.color
            opacity: 0
            visible: ping.running
        }
    }
    SequentialAnimation {
        id: ping
        running: spark.pulse && spark.running && spark._drawn >= 1 && spark.visible && spark.count > 1
                 && Device.animatedTiles && !Device.idle
        loops: 3
        onStopped: { ring.opacity = 0; ring.scale = 1 }
        ParallelAnimation {
            ScaleAnimator { target: ring; from: 1; to: 3.2; duration: Theme.breath; easing.type: Easing.OutSine }
            OpacityAnimator { target: ring; from: 0.55; to: 0; duration: Theme.breath; easing.type: Easing.OutSine }
        }
        PauseAnimation { duration: Theme.breath / 2 }
    }
}
