import QtQuick
import QtQuick.Shapes
import McFly

// Progress as a ring: a faint track all the way round and an arc over it
// from 12 o'clock, clockwise, with round ends. `shown` scales the arc (a
// screen's reveal, so it sweeps in with the page); children sit in the
// middle (the number).
//
//   Ring { value: project.progress / 100; shown: rv.at(index); color: project.statusColor
//          Label { anchors.centerIn: parent; text: project.progress + "%" } }
//
// The arc is a Shape, rebuilt when its sweep changes: fine for an entrance
// or a minute's tick, not for a loop (spin the whole item with an Animator).
Item {
    id: ring
    property real value: 0               // 0..1
    property real shown: 1               // 0..1, multiplies the sweep
    property color color: Theme.accent
    property color track: Qt.rgba(color.r, color.g, color.b, 0.16)
    property real lineWidth: Math.max(4, Math.round(size * 0.09))
    // Where the arc starts, in degrees clockwise from 12 o'clock.
    property real startAngle: 0

    default property alias content: middle.data

    readonly property real size: Math.min(width, height)
    // Drawn in software (a fallback, and offscreen pictures), a path redrawn
    // every frame costs a lot and can smear past its clip: no sweep in.
    readonly property bool _sweeps: GraphicsInfo.api !== GraphicsInfo.Software
    readonly property real sweep: 360 * Math.max(0, Math.min(1, value)) * (_sweeps ? Math.max(0, Math.min(1, shown)) : 1)
    readonly property real _r: (size - lineWidth) / 2

    implicitWidth: 64
    implicitHeight: 64

    Shape {
        anchors.fill: parent
        visible: ring._r > 0
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: ring.track
            strokeWidth: ring.lineWidth
            fillColor: "transparent"
            PathAngleArc {
                centerX: ring.width / 2; centerY: ring.height / 2
                radiusX: ring._r; radiusY: ring._r
                startAngle: 0; sweepAngle: 360
            }
        }
    }
    // Its own Shape, so the track isn't rebuilt with the sweep.
    Shape {
        anchors.fill: parent
        // A zero sweep with round caps would still draw a dot.
        visible: ring._r > 0 && ring.sweep > 0.5
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: ring.color
            strokeWidth: ring.lineWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: ring.width / 2; centerY: ring.height / 2
                radiusX: ring._r; radiusY: ring._r
                // PathAngleArc counts from 3 o'clock.
                startAngle: ring.startAngle - 90
                sweepAngle: ring.sweep
            }
        }
    }
    Item {
        id: middle
        anchors.fill: parent
    }
}
