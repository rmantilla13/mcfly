import QtQuick
import QtQuick.Shapes
import McFly

// A price history as a thin line with a soft fill under it. The points are
// plain numbers (oldest first); the line is scaled to fill the item with a
// little headroom. Up days are green, down days coral.
Item {
    id: spark
    property var points: []
    property color color: Theme.success
    property real lineWidth: 3

    readonly property int count: points ? points.length : 0
    readonly property real low: count > 0 ? Math.min.apply(null, points) : 0
    readonly property real high: count > 0 ? Math.max.apply(null, points) : 1
    readonly property real span: high - low > 0 ? high - low : (high !== 0 ? Math.abs(high) * 0.02 : 1)

    function xAt(i) { return count > 1 ? i * width / (count - 1) : width / 2 }
    function yAt(v) { return height - 4 - (v - low) / span * (height - 8) }

    // The path is rebuilt only when the points change, not every frame.
    property string linePath: ""
    property string fillPath: ""
    function rebuild() {
        if (count < 2 || width <= 0 || height <= 0) {
            linePath = ""
            fillPath = ""
            return
        }
        var d = "M " + xAt(0) + " " + yAt(points[0])
        for (var i = 1; i < count; i++)
            d += " L " + xAt(i) + " " + yAt(points[i])
        linePath = d
        fillPath = d + " L " + width + " " + height + " L 0 " + height + " Z"
    }
    onPointsChanged: rebuild()
    onWidthChanged: rebuild()
    onHeightChanged: rebuild()
    Component.onCompleted: rebuild()

    Shape {
        anchors.fill: parent
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
    // The newest point.
    Rectangle {
        visible: spark.count > 1
        x: spark.width - width / 2
        y: spark.count > 0 ? spark.yAt(spark.points[spark.count - 1]) - height / 2 : 0
        width: spark.lineWidth * 2.4; height: width; radius: width / 2
        color: spark.color
    }
}
