import QtQuick
import McFly

// What Scoop Shop's buttons show: a tub of a flavour in the freezer case,
// a stack of cones or of cups, a jar of a topping. Drawn in a square that
// fits the box, standing on its bottom edge.
Item {
    id: stock
    // "vanilla", "chocolate", "strawberry", "mint", "cone", "cup",
    // "sprinkles", "cherry" or "wafer".
    property string key: "vanilla"
    readonly property bool tub: ["vanilla", "chocolate", "strawberry", "mint"].indexOf(key) >= 0
    readonly property bool jar: ["sprinkles", "cherry", "wafer"].indexOf(key) >= 0
    readonly property real s: Math.min(width, height)
    readonly property bool dark: Theme.dark

    Item {
        id: box
        width: stock.s
        height: stock.s
        x: (stock.width - width) / 2
        y: stock.height - height

        // ---- A tub: a steel pan of the flavour, a scoop rolled on top.
        Item {
            anchors.fill: parent
            visible: stock.tub
            readonly property var f: treatRef.flavours[stock.key] || treatRef.flavours.vanilla
            Rectangle {
                x: box.width * 0.12
                y: box.height * 0.36
                width: box.width * 0.76
                height: box.height * 0.34
                radius: height / 2
                color: parent.f.fill
                border.width: Math.max(1, box.width * 0.02)
                border.color: treatRef.rim(stock.key)
                Repeater {
                    model: [[0.22, 0.3, 20], [0.55, 0.22, -30], [0.72, 0.45, 50]]
                    delegate: Rectangle {
                        required property var modelData
                        x: parent.width * modelData[0]
                        y: parent.height * modelData[1]
                        width: parent.width * (stock.key === "vanilla" ? 0.04 : 0.07)
                        height: width * 0.75
                        radius: width / 3
                        rotation: modelData[2]
                        color: parent.parent.f.bits
                        opacity: stock.key === "chocolate" ? 0.55 : 0.9
                    }
                }
            }
            ScoopTreat {
                id: treatRef
                x: box.width * 0.36
                y: box.height * 0.08
                width: box.width * 0.44
                height: box.height * 0.42
                scoops: stock.tub ? [stock.key] : []
                units: 3.0
            }
            // The pan, in front of the ice cream.
            Rectangle {
                x: box.width * 0.04
                y: box.height * 0.56
                width: box.width * 0.92
                height: box.height * 0.08
                radius: height / 2
                color: stock.dark ? "#C7D0D8" : "#DCE3E9"
            }
            Rectangle {
                x: box.width * 0.08
                y: box.height * 0.62
                width: box.width * 0.84
                height: box.height * 0.34
                radius: box.width * 0.05
                gradient: Gradient {
                    GradientStop { position: 0; color: stock.dark ? "#A9B4BE" : "#C3CCD4" }
                    GradientStop { position: 1; color: stock.dark ? "#7E8A95" : "#98A4AF" }
                }
                Rectangle {
                    x: parent.width * 0.06
                    y: parent.height * 0.18
                    width: parent.width * 0.88
                    height: Math.max(1, parent.height * 0.06)
                    color: "white"
                    opacity: 0.45
                }
            }
        }

        // ---- A stack of cones, or of cups, one in another.
        Repeater {
            model: stock.key === "cone" || stock.key === "cup" ? 3 : 0
            delegate: ScoopTreat {
                required property int index
                width: box.width
                height: box.height
                base: stock.key
                units: stock.key === "cone" ? 6.4 : 5.6
                lift: 0.15 + (2 - index) * (stock.key === "cone" ? 0.85 : 0.7)
            }
        }

        // ---- A jar: what's in it, the glass over that, a lid.
        Item {
            anchors.fill: parent
            visible: stock.jar
            readonly property color lidColor: stock.key === "sprinkles" ? "#F28DB2" : stock.key === "cherry" ? "#4E9D5B" : "#E8BC74"
            // Wafers stand up out of an open jar.
            Repeater {
                model: stock.key === "wafer" ? [[0.34, -8], [0.47, 4], [0.58, 12]] : []
                delegate: Rectangle {
                    required property var modelData
                    x: box.width * modelData[0]
                    y: box.height * 0.1
                    width: box.width * 0.1
                    height: box.height * 0.62
                    radius: width * 0.25
                    rotation: modelData[1]
                    color: "#E8BC74"
                    border.width: Math.max(1, box.width * 0.015)
                    border.color: "#B98A42"
                    Repeater {
                        model: 4
                        delegate: Rectangle {
                            required property int index
                            x: parent.width * 0.15
                            y: parent.height * (0.15 + index * 0.18)
                            width: parent.width * 0.7
                            height: Math.max(1, box.width * 0.012)
                            color: "#B98A42"
                        }
                    }
                }
            }
            Repeater {
                model: stock.key === "sprinkles"
                       ? [[0.30, 0.62, 20, "#E5484D"], [0.45, 0.70, -40, "#5B8DEF"], [0.60, 0.60, 70, "#F2B84B"],
                          [0.36, 0.80, -10, "#3DB37A"], [0.55, 0.84, 35, "#8E7CE6"], [0.66, 0.74, -60, "#E5484D"],
                          [0.28, 0.72, 80, "#F2B84B"], [0.48, 0.58, -70, "#3DB37A"], [0.40, 0.90, 15, "#5B8DEF"],
                          [0.62, 0.90, -25, "#FFFFFF"], [0.52, 0.77, 55, "#F28DB2"], [0.33, 0.52, -30, "#8E7CE6"]]
                       : []
                delegate: Rectangle {
                    required property var modelData
                    x: box.width * modelData[0]
                    y: box.height * modelData[1]
                    width: box.width * 0.1
                    height: Math.max(2, box.width * 0.035)
                    radius: height / 2
                    rotation: modelData[2]
                    color: modelData[3]
                }
            }
            Repeater {
                model: stock.key === "cherry" ? [[0.30, 0.72], [0.50, 0.74], [0.40, 0.56], [0.58, 0.58]] : []
                delegate: Rectangle {
                    required property var modelData
                    x: box.width * modelData[0]
                    y: box.height * modelData[1]
                    width: box.width * 0.18
                    height: width
                    radius: width / 2
                    color: "#D8263C"
                    border.width: Math.max(1, box.width * 0.015)
                    border.color: "#9E1428"
                    Rectangle {
                        x: parent.width * 0.2
                        y: parent.height * 0.18
                        width: parent.width * 0.28
                        height: width
                        radius: width / 2
                        color: "white"
                        opacity: 0.6
                    }
                }
            }
            // The glass.
            Rectangle {
                x: box.width * 0.2
                y: box.height * 0.36
                width: box.width * 0.6
                height: box.height * 0.6
                radius: box.width * 0.1
                color: Qt.rgba(1, 1, 1, stock.dark ? 0.14 : 0.32)
                border.width: Math.max(1, box.width * 0.025)
                border.color: stock.dark ? "#9FB0BE" : "#B9C6D1"
                Rectangle {
                    x: parent.width * 0.12
                    y: parent.height * 0.12
                    width: parent.width * 0.1
                    height: parent.height * 0.62
                    radius: width / 2
                    color: "white"
                    opacity: stock.dark ? 0.35 : 0.7
                }
            }
            Rectangle {
                visible: stock.key !== "wafer"
                x: box.width * 0.16
                y: box.height * 0.27
                width: box.width * 0.68
                height: box.height * 0.11
                radius: box.width * 0.04
                color: parent.lidColor
                border.width: Math.max(1, box.width * 0.015)
                border.color: Qt.darker(parent.lidColor, 1.25)
            }
        }
    }
}
