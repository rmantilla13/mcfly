import QtQuick
import QtQuick.Shapes
import McFly

// Scoop Shop's two shopkeepers, drawn for McFly: Pip the penguin and Lotl
// the axolotl, each in the shop's paper hat. `mood` is "" (at work),
// "happy" (an order went out right: a hop and a squint) or "oops" (a wrong
// order or a customer gone: a shake). With `panic` (a customer about to
// give up) they sweat, look worried and tremble. They are drawn on a 10 × 12 grid,
// scaled to fit and standing on the bottom edge.
Item {
    id: crew
    property string who: "pip"
    property string mood: ""
    property bool panic: false

    readonly property real k: Math.max(0, Math.min(width / 10, height / 12))
    readonly property bool happy: mood === "happy"
    readonly property bool oops: mood === "oops"
    readonly property bool worried: panic && mood === ""
    readonly property bool dark: Theme.dark

    // In software, one picture rather than loose shapes (see ScoopTreat),
    // with room round it for the hop and the shake.
    layer.enabled: GraphicsInfo.api === GraphicsInfo.Software
    layer.sourceRect: Qt.rect(-k, -2 * k, width + 2 * k, height + 2 * k)

    property real hop: 0
    property real shake: 0
    property real tremble: 0
    SequentialAnimation on tremble {
        running: crew.worried && crew.visible
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 40 }
        NumberAnimation { to: -1; duration: 80 }
        NumberAnimation { to: 0; duration: 40 }
        PauseAnimation { duration: 180 }
    }
    onWorriedChanged: if (!worried) tremble = 0
    onMoodChanged: {
        if (happy)
            hopAnim.restart()
        else if (oops)
            shakeAnim.restart()
    }
    SequentialAnimation {
        id: hopAnim
        NumberAnimation { target: crew; property: "hop"; to: 1; duration: 160; easing.type: Easing.OutQuad }
        NumberAnimation { target: crew; property: "hop"; to: 0; duration: 220; easing.type: Easing.InQuad }
    }
    SequentialAnimation {
        id: shakeAnim
        loops: 2
        NumberAnimation { target: crew; property: "shake"; to: -1; duration: 60 }
        NumberAnimation { target: crew; property: "shake"; to: 1; duration: 120 }
        NumberAnimation { target: crew; property: "shake"; to: 0; duration: 60 }
    }

    // A k-unit rectangle, for the parts below.
    component Part: Rectangle {
        property real px
        property real py
        property real pw
        property real ph
        x: px * crew.k
        y: py * crew.k
        width: pw * crew.k
        height: ph * crew.k
        radius: Math.min(width, height) / 2
    }

    Item {
        id: figure
        width: 10 * crew.k
        height: 12 * crew.k
        x: (crew.width - width) / 2 + (crew.shake + crew.tremble * 0.6) * 0.35 * crew.k
        y: crew.height - height - crew.hop * 1.1 * crew.k

        // ================= Pip, the penguin
        Item {
            anchors.fill: parent
            visible: crew.who === "pip"
            readonly property color navy: "#34405C"
            readonly property color edge: crew.dark ? "#7083B0" : "#27314A"
            readonly property color cream: "#FFF6E6"
            readonly property color orange: "#F39A3B"

            Part { px: 2.6; py: 11.0; pw: 2.2; ph: 0.95; color: parent.orange }
            Part { px: 5.2; py: 11.0; pw: 2.2; ph: 0.95; color: parent.orange }
            Part { px: 0.85; py: 5.0; pw: 1.3; ph: 4.4; rotation: 18; color: parent.navy; border.width: crew.k * 0.16; border.color: parent.edge }
            Part { px: 7.85; py: 5.0; pw: 1.3; ph: 4.4; rotation: -18; color: parent.navy; border.width: crew.k * 0.16; border.color: parent.edge }
            Part { px: 1.5; py: 1.0; pw: 7.0; ph: 10.4; color: parent.navy; border.width: crew.k * 0.18; border.color: parent.edge }
            // The white front: a mask round the eyes running into the belly.
            Part { px: 2.6; py: 5.0; pw: 4.8; ph: 5.9; color: parent.cream }
            Part { px: 2.3; py: 2.1; pw: 3.2; ph: 3.2; color: parent.cream }
            Part { px: 4.5; py: 2.1; pw: 3.2; ph: 3.2; color: parent.cream }
            Repeater {
                model: [4.0, 6.0]
                delegate: Part {
                    required property real modelData
                    px: modelData - 0.43
                    py: crew.happy ? 3.5 : 3.18
                    pw: 0.86
                    ph: crew.happy ? 0.3 : 0.86
                    color: "#1E2333"
                    Rectangle {
                        visible: !crew.happy
                        x: parent.width * 0.18
                        y: parent.height * 0.14
                        width: parent.width * 0.36
                        height: width
                        radius: width / 2
                        color: "white"
                    }
                }
            }
            Part { px: 2.6; py: 4.45; pw: 1.0; ph: 0.55; color: "#FF9AAE"; opacity: 0.75 }
            Part { px: 6.4; py: 4.45; pw: 1.0; ph: 0.55; color: "#FF9AAE"; opacity: 0.75 }
            Part { px: 4.48; py: 3.95; pw: 1.04; ph: 1.04; radius: crew.k * 0.22; rotation: 45; color: parent.orange }
            // Drops of worry.
            Part { visible: crew.oops || crew.worried; px: 8.3; py: 1.6; pw: 0.7; ph: 1.0; color: "#7CC4F2" }
            Part { visible: crew.worried; px: 1.0; py: 2.4; pw: 0.6; ph: 0.85; color: "#7CC4F2" }
            // Brows up in the middle.
            Part { visible: crew.worried; px: 3.45; py: 2.55; pw: 1.1; ph: 0.24; rotation: -18; color: "#1E2333" }
            Part { visible: crew.worried; px: 5.45; py: 2.55; pw: 1.1; ph: 0.24; rotation: 18; color: "#1E2333" }
        }

        // ================= Lotl, the axolotl
        Item {
            anchors.fill: parent
            visible: crew.who === "lotl"
            readonly property color pink: "#F6A8C3"
            readonly property color edge: crew.dark ? "#FFD0E0" : "#E07FA3"
            readonly property color gill: "#E2558A"

            Part { px: 6.1; py: 9.3; pw: 3.4; ph: 1.3; rotation: -25; color: "#F09AB8"; border.width: crew.k * 0.14; border.color: parent.edge }
            Part { px: 2.9; py: 11.0; pw: 1.6; ph: 0.9; color: "#F09AB8" }
            Part { px: 5.5; py: 11.0; pw: 1.6; ph: 0.9; color: "#F09AB8" }
            Part { px: 1.9; py: 7.3; pw: 1.1; ph: 2.4; rotation: 25; color: parent.pink; border.width: crew.k * 0.14; border.color: parent.edge }
            Part { px: 7.0; py: 7.3; pw: 1.1; ph: 2.4; rotation: -25; color: parent.pink; border.width: crew.k * 0.14; border.color: parent.edge }
            Part { px: 2.6; py: 6.2; pw: 4.8; ph: 5.3; color: parent.pink; border.width: crew.k * 0.16; border.color: parent.edge }
            Part { px: 3.5; py: 7.3; pw: 3.0; ph: 3.5; color: "#FDD9E5" }
            // Three feathery gills on each side, fanning out from the head.
            Repeater {
                model: [[2.8, 28], [3.95, 0], [5.1, -28]]
                delegate: Item {
                    id: gills
                    required property var modelData
                    Repeater {
                        model: [-1, 1]
                        delegate: Part {
                            required property int modelData
                            px: modelData < 0 ? 0.0 : 7.8
                            py: gills.modelData[0] - 0.38
                            pw: 2.2
                            ph: 0.76
                            transformOrigin: modelData < 0 ? Item.Right : Item.Left
                            rotation: gills.modelData[1] * -modelData
                            color: "#E2558A"
                            Repeater {
                                model: 2
                                delegate: Rectangle {
                                    required property int index
                                    x: parent.width * (0.18 + index * 0.34)
                                    y: -parent.height * 0.25
                                    width: parent.height * 0.62
                                    height: width
                                    radius: width / 2
                                    color: "#EE77A2"
                                }
                            }
                        }
                    }
                }
            }
            Part { px: 1.4; py: 1.6; pw: 7.2; ph: 5.2; radius: crew.k * 2.5; color: parent.pink; border.width: crew.k * 0.16; border.color: parent.edge }
            Repeater {
                model: [3.3, 6.7]
                delegate: Part {
                    required property real modelData
                    px: modelData - 0.4
                    py: crew.happy ? 3.85 : 3.5
                    pw: 0.8
                    ph: crew.happy ? 0.3 : 0.8
                    color: "#2B1E2A"
                    Rectangle {
                        visible: !crew.happy
                        x: parent.width * 0.18
                        y: parent.height * 0.14
                        width: parent.width * 0.36
                        height: width
                        radius: width / 2
                        color: "white"
                    }
                }
            }
            Part { px: 2.2; py: 4.55; pw: 1.0; ph: 0.55; color: "#FF7FA8"; opacity: 0.6 }
            Part { px: 6.8; py: 4.55; pw: 1.0; ph: 0.55; color: "#FF7FA8"; opacity: 0.6 }
            // Drops of worry, and brows up in the middle.
            Part { visible: crew.oops || crew.worried; px: 8.0; py: 0.9; pw: 0.7; ph: 1.0; color: "#7CC4F2" }
            Part { visible: crew.worried; px: 1.4; py: 1.2; pw: 0.6; ph: 0.85; color: "#7CC4F2" }
            Part { visible: crew.worried; px: 2.8; py: 2.85; pw: 1.1; ph: 0.24; rotation: -18; color: "#2B1E2A" }
            Part { visible: crew.worried; px: 6.1; py: 2.85; pw: 1.1; ph: 0.24; rotation: 18; color: "#2B1E2A" }
            // A smile, a wider one when happy, an "o" when not.
            Shape {
                visible: !crew.oops && !crew.worried
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: "#9A3A60"
                    strokeWidth: Math.max(1.5, crew.k * 0.24)
                    capStyle: ShapePath.RoundCap
                    PathSvg {
                        readonly property real w: crew.happy ? 1.2 : 0.8
                        path: "M %1 %2 Q %3 %4 %5 %2".arg((5 - w) * crew.k).arg(4.7 * crew.k).arg(5 * crew.k)
                                                      .arg((crew.happy ? 5.9 : 5.4) * crew.k).arg((5 + w) * crew.k)
                    }
                }
            }
            Part { visible: crew.oops || crew.worried; px: 4.7; py: 4.75; pw: 0.6; ph: 0.6; color: "transparent"; border.width: crew.k * 0.22; border.color: "#9A3A60" }
        }

        // ================= The shop's paper hat, on both
        Part {
            px: 3.0
            py: crew.who === "pip" ? 0.25 : 0.65
            pw: 4.0
            ph: 1.3
            radius: crew.k * 0.4
            rotation: -6
            color: "#FFFFFF"
            border.width: crew.k * 0.1
            border.color: "#D9D2CA"
            Rectangle {
                y: parent.height * 0.42
                width: parent.width
                height: parent.height * 0.3
                color: "#56C3A0"
            }
        }
    }
}
