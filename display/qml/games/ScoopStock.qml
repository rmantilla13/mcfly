import QtQuick
import McFly
import "scoops.js" as Scoops

// What Scoop Shop's buttons show: a tub of a flavour in the freezer case,
// a stack of cones or of cups, a jar of a topping (a squeeze bottle of
// syrup, a bowl of whipped cream). Drawn in a square that fits the box,
// standing on its bottom edge.
Item {
    id: stock
    // A flavour, "cone" or "cup", or a topping (scoops.js).
    property string key: "vanilla"
    readonly property bool tub: Scoops.FLAVOURS.indexOf(key) >= 0
    readonly property bool jar: ["sprinkles", "cherry", "wafer", "crunch", "rings"].indexOf(key) >= 0
    // Never below 0: a button smaller than its padding and label lays this
    // out at a negative size, and everything here scales from s.
    readonly property real s: Math.max(0, Math.min(width, height))
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
            readonly property color lidColor: ({ sprinkles: "#F28DB2", cherry: "#4E9D5B", wafer: "#E8BC74",
                                                  crunch: "#B9793A", rings: "#9B6BD8" })[stock.key] || "#E8BC74"
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
            Repeater {
                model: stock.key === "crunch"
                       ? [[0.28, 0.66, 20, "#F0BE62"], [0.42, 0.74, -30, "#8E5726"], [0.56, 0.62, 45, "#E3A94F"],
                          [0.34, 0.84, -15, "#E3A94F"], [0.5, 0.86, 30, "#F0BE62"], [0.62, 0.78, -40, "#8E5726"],
                          [0.3, 0.55, 60, "#F7D486"], [0.46, 0.52, 10, "#8E5726"], [0.6, 0.5, -60, "#F0BE62"]]
                       : []
                delegate: Rectangle {
                    required property var modelData
                    x: box.width * modelData[0]
                    y: box.height * modelData[1]
                    width: box.width * 0.1
                    height: box.width * 0.08
                    radius: width * 0.25
                    rotation: modelData[2]
                    color: modelData[3]
                }
            }
            Repeater {
                model: stock.key === "rings"
                       ? [[0.27, 0.74, "#E5484D"], [0.45, 0.8, "#F2CF3B"], [0.6, 0.72, "#4DBF6A"],
                          [0.34, 0.58, "#9B6BD8"], [0.52, 0.6, "#F59A2F"], [0.42, 0.44, "#E5484D"]]
                       : []
                delegate: Rectangle {
                    required property var modelData
                    x: box.width * modelData[0]
                    y: box.height * modelData[1]
                    width: box.width * 0.15
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: Math.max(2, box.width * 0.045)
                    border.color: modelData[2]
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

        // ---- A squeeze bottle of chocolate syrup.
        Item {
            anchors.fill: parent
            visible: stock.key === "syrup"
            Rectangle {
                x: box.width * 0.47
                y: box.height * 0.1
                width: box.width * 0.06
                height: box.height * 0.16
                radius: width / 2
                color: "#D8263C"
            }
            Rectangle {
                x: box.width * 0.38
                y: box.height * 0.22
                width: box.width * 0.24
                height: box.height * 0.13
                radius: box.width * 0.04
                color: "#D8263C"
                border.width: Math.max(1, box.width * 0.015)
                border.color: "#9E1428"
            }
            Rectangle {
                x: box.width * 0.3
                y: box.height * 0.33
                width: box.width * 0.4
                height: box.height * 0.63
                radius: box.width * 0.1
                color: "#5A2E1A"
                border.width: Math.max(1, box.width * 0.015)
                border.color: stock.dark ? "#A0705A" : "#3A1C0F"
                Rectangle {
                    y: parent.height * 0.34
                    width: parent.width
                    height: parent.height * 0.3
                    color: "#F6E2C0"
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.36
                        height: parent.height * 0.5
                        radius: height / 2
                        color: "#5A2E1A"
                    }
                }
                Rectangle {
                    x: parent.width * 0.14
                    y: parent.height * 0.06
                    width: parent.width * 0.12
                    height: parent.height * 0.24
                    radius: width / 2
                    color: "white"
                    opacity: 0.4
                }
            }
        }

        // ---- A bowl of whipped cream.
        Item {
            anchors.fill: parent
            visible: stock.key === "cream"
            Repeater {
                model: [[0.18, 0.5, 0.64, 0.2], [0.26, 0.38, 0.48, 0.17], [0.35, 0.28, 0.3, 0.14], [0.45, 0.2, 0.12, 0.12]]
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    x: box.width * modelData[0]
                    y: box.height * modelData[1]
                    width: box.width * modelData[2]
                    height: box.height * modelData[3]
                    radius: height / 2
                    rotation: index === 3 ? 20 : 0
                    color: "#FFFFFF"
                    border.width: Math.max(1, box.width * 0.015)
                    border.color: stock.dark ? "#E8E2DA" : "#D8D0C4"
                }
            }
            Rectangle {
                x: box.width * 0.12
                y: box.height * 0.62
                width: box.width * 0.76
                height: box.height * 0.32
                topLeftRadius: box.width * 0.04
                topRightRadius: box.width * 0.04
                bottomLeftRadius: height * 0.9
                bottomRightRadius: height * 0.9
                color: stock.dark ? "#6E9DB6" : "#BFE0F2"
                border.width: Math.max(1, box.width * 0.015)
                border.color: stock.dark ? "#9CC4D8" : "#8FC1DC"
                Rectangle {
                    x: parent.width * 0.1
                    y: parent.height * 0.18
                    width: parent.width * 0.5
                    height: Math.max(1, parent.height * 0.1)
                    radius: height / 2
                    color: "white"
                    opacity: 0.6
                }
            }
        }
    }
}
