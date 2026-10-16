import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import McFly
import McFly.Core

// Today's price laid out on the whole session, as a broker's day chart: the
// line runs from the open as far as the latest bar and the rest of the day
// is still to come, a dashed line marks the previous close, and the session's
// times sit under it. The store does the shaping (FeedStore::intradayOf):
// `points` are { x, y } in 0..1, `baseY` is the previous close's height
// (-1 without one). Coloured by where the price sits against that close.
Item {
    id: chart
    property var points: []
    property real baseY: -1
    property color color: Theme.gain
    property color baseColor: Theme.textMuted
    property color labelColor: Theme.textMuted
    property real lineWidth: 3
    property string openLabel: ""
    property string closeLabel: ""
    // Draws on from the left, as the Sparkline does on a screen's reveal.
    property real progress: 1

    readonly property int count: points ? points.length : 0
    readonly property real labelHeight: openLabel !== "" ? times.implicitHeight + 6 : 0
    readonly property real plotHeight: Math.max(0, height - labelHeight)
    readonly property real pad: 6

    function px(x) { return x * width }
    function py(y) { return pad + (1 - y) * (plotHeight - 2 * pad) }

    // Rebuilt only when the points or the size change.
    property string linePath: ""
    property string fillPath: ""
    function rebuild() {
        const pts = points || []
        if (pts.length < 2 || width <= 0 || plotHeight <= 0) {
            linePath = ""
            fillPath = ""
            return
        }
        var d = "M " + px(pts[0].x) + " " + py(pts[0].y)
        for (var i = 1; i < pts.length; i++)
            d += " L " + px(pts[i].x) + " " + py(pts[i].y)
        linePath = d
        fillPath = d + " L " + px(pts[pts.length - 1].x) + " " + plotHeight + " L " + px(pts[0].x) + " " + plotHeight + " Z"
    }
    onPointsChanged: rebuild()
    onWidthChanged: rebuild()
    onPlotHeightChanged: rebuild()
    Component.onCompleted: rebuild()

    readonly property real _drawn: GraphicsInfo.api === GraphicsInfo.Software ? 1 : Math.max(0, Math.min(1, progress))

    // The previous close, across the whole session.
    Shape {
        visible: chart.baseY >= 0 && chart.count > 1
        width: chart.width
        height: chart.plotHeight
        ShapePath {
            strokeColor: Qt.rgba(chart.baseColor.r, chart.baseColor.g, chart.baseColor.b, 0.6)
            strokeWidth: 1.5
            strokeStyle: ShapePath.DashLine
            dashPattern: [3, 4]
            fillColor: "transparent"
            startX: 0; startY: chart.py(chart.baseY)
            PathLine { x: chart.width; y: chart.py(chart.baseY) }
        }
    }

    Item {
        width: Math.round(chart.width * chart._drawn)
        height: chart.plotHeight
        clip: chart._drawn < 1
        Shape {
            width: chart.width
            height: chart.plotHeight
            visible: chart.fillPath !== ""
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"
                fillGradient: LinearGradient {
                    x1: 0; y1: 0; x2: 0; y2: chart.plotHeight
                    GradientStop { position: 0; color: Qt.rgba(chart.color.r, chart.color.g, chart.color.b, 0.26) }
                    GradientStop { position: 1; color: Qt.rgba(chart.color.r, chart.color.g, chart.color.b, 0.0) }
                }
                PathSvg { path: chart.fillPath }
            }
            ShapePath {
                strokeColor: chart.color
                strokeWidth: chart.lineWidth
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: chart.linePath }
            }
        }
    }

    // Now: the newest point, once the line has reached it.
    Rectangle {
        visible: chart.count > 1
        readonly property var lastPoint: chart.count > 0 ? chart.points[chart.count - 1] : ({ x: 0, y: 0 })
        x: chart.px(lastPoint.x) - width / 2
        y: chart.py(lastPoint.y) - height / 2
        width: chart.lineWidth * 2.6; height: width; radius: width / 2
        color: chart.color
        opacity: Math.max(0, Math.min(1, (chart._drawn - 0.9) * 10))
    }

    // The session's ends.
    Item {
        id: times
        visible: chart.openLabel !== ""
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        implicitHeight: openText.implicitHeight
        height: implicitHeight
        Label { id: openText; anchors.left: parent.left; text: chart.openLabel; color: chart.labelColor; font.pixelSize: Theme.fontXs }
        Label { anchors.right: parent.right; text: chart.closeLabel; color: chart.labelColor; font.pixelSize: Theme.fontXs }
    }
}
