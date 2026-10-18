import QtQuick
import QtQuick.Shapes
import McFly

// One of Scoop Shop's treats, drawn: a cone or a cup, the scoops on it from
// the bottom up, the toppings on the top scoop. A customer's ticket, the
// one being built and the card on the Games list all use it, so an order
// reads the same everywhere.
//
// It draws to a unit `u`: at the default 12 units tall a cone with three
// scoops and a cherry fits, and every ticket is at the same scale whatever
// is on it. A button's icon sets `units` to its one piece and `lift` to
// raise it off the bottom.
Item {
    id: treat
    property string base: ""
    property var scoops: []
    property var toppings: []
    property real units: 12
    property real lift: 0

    readonly property real u: Math.max(0, Math.min(width / 5, height / units))
    readonly property bool dark: Theme.dark

    // Drawn in software (the offscreen pictures, a panel with no GPU), a
    // Shape that moves leaves its old place painted and paints past a
    // scrolling list's clip. There the treat is one picture, which moves and
    // clips as it should. The GPU draws the shapes as they are.
    layer.enabled: GraphicsInfo.api === GraphicsInfo.Software

    readonly property var flavours: ({
        vanilla: { fill: "#F7E6B0", rim: "#D7B86C", bits: "#B88A4E" },
        chocolate: { fill: "#8B5332", rim: "#5C331C", bits: "#C9946A" },
        strawberry: { fill: "#F59BB6", rim: "#D7638A", bits: "#C9374F" },
        mint: { fill: "#9FE2C4", rim: "#56AE8A", bits: "#3B271C" }
    })
    // On the dark canvas a dark rim disappears: lift it instead.
    function rim(f) {
        const c = flavours[f] || flavours.vanilla
        return dark ? Qt.lighter(c.fill, f === "chocolate" ? 1.7 : 1.15) : c.rim
    }

    // Heights, in units, up from the bottom (0) of the art.
    readonly property real vesselHeight: base === "cone" ? 4.2 : base === "cup" ? 3.2 : 0
    readonly property real r: 1.6 // a scoop's radius
    // A scoop's centre: the first sits in the vessel's mouth, each next one
    // on the one under it.
    function scoopY(i) { return -vesselHeight + (base ? 0.5 : 0) - 0.53 * r - 1.85 * i }
    readonly property int count: scoops ? scoops.length : 0
    // Where the toppings go: the top scoop, or loose in the middle (an icon).
    readonly property real topY: count > 0 ? scoopY(count - 1) : -units / 2

    // The art's origin: the bottom centre.
    Item {
        id: art
        x: treat.width / 2
        y: treat.height - treat.lift * treat.u

        // ---- The cone: waffle, a lip, a crosshatch inside its edges.
        Shape {
            visible: treat.base === "cone"
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "#E5A653"
                strokeColor: treat.dark ? "#F0C182" : "#B5772F"
                strokeWidth: Math.max(1, treat.u * 0.12)
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    readonly property real u: treat.u
                    path: "M %1 %2 L %3 %2 L 0 0 Z".arg(-1.7 * u).arg(-4.2 * u).arg(1.7 * u)
                }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: "#BF8037"
                strokeWidth: Math.max(1, treat.u * 0.12)
                capStyle: ShapePath.RoundCap
                PathSvg {
                    // Lines from the cone's top edge to the far side, both ways.
                    path: {
                        const u = treat.u, h = 4.2, w = 1.7
                        let d = ""
                        for (const x0 of [-0.95, -0.1, 0.75]) {
                            const s = (w - x0) / (2 * w)
                            d += "M %1 %2 L %3 %4 ".arg(x0 * u).arg(-h * u).arg((x0 + w * s) * u).arg((-h + h * s) * u)
                            d += "M %1 %2 L %3 %4 ".arg(-x0 * u).arg(-h * u).arg(-(x0 + w * s) * u).arg((-h + h * s) * u)
                        }
                        return d
                    }
                }
            }
        }
        Rectangle {
            visible: treat.base === "cone"
            x: -1.85 * treat.u
            y: -4.45 * treat.u
            width: 3.7 * treat.u
            height: 0.6 * treat.u
            radius: height / 2
            color: "#D08C40"
        }

        // ---- The cup: paper, a white band, a rim.
        Shape {
            visible: treat.base === "cup"
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "#7DC4E6"
                strokeColor: treat.dark ? "#A9DBF2" : "#4E9DC4"
                strokeWidth: Math.max(1, treat.u * 0.12)
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    readonly property real u: treat.u
                    path: "M %1 %2 L %3 %2 L %4 0 L %5 0 Z".arg(-2 * u).arg(-3.2 * u).arg(2 * u).arg(1.5 * u).arg(-1.5 * u)
                }
            }
            ShapePath {
                fillColor: "#FFFFFF"
                strokeColor: "transparent"
                PathSvg {
                    readonly property real u: treat.u
                    // The band between 1.2 and 2.0 units up, along the slanted sides.
                    path: "M %1 %2 L %3 %2 L %4 %5 L %6 %5 Z".arg(-1.81 * u).arg(-2.0 * u).arg(1.81 * u)
                                                              .arg(1.69 * u).arg(-1.2 * u).arg(-1.69 * u)
                }
            }
        }
        Rectangle {
            visible: treat.base === "cup"
            x: -2.2 * treat.u
            y: -3.5 * treat.u
            width: 4.4 * treat.u
            height: 0.6 * treat.u
            radius: height / 2
            color: "#5AAED6"
        }

        // ---- The wafer goes in behind the top scoop.
        Rectangle {
            visible: treat.toppings.indexOf("wafer") >= 0
            z: treat.count - 0.5
            x: 0.25 * treat.u
            y: (treat.count > 0 ? treat.topY - 2.6 : treat.topY - 1.5) * treat.u
            width: 0.7 * treat.u
            height: 3.0 * treat.u
            radius: 0.2 * treat.u
            rotation: 28
            color: "#E8BC74"
            border.width: Math.max(1, treat.u * 0.1)
            border.color: treat.dark ? "#F5D9A8" : "#B98A42"
            Repeater {
                model: 3
                delegate: Rectangle {
                    required property int index
                    x: parent.width * 0.15
                    y: parent.height * (0.25 + index * 0.25)
                    width: parent.width * 0.7
                    height: Math.max(1, treat.u * 0.1)
                    color: "#B98A42"
                }
            }
        }

        // ---- Scoops, bottom first: each one over the one under it.
        Repeater {
            model: treat.scoops
            delegate: Item {
                id: scoop
                required property string modelData
                required property int index
                readonly property var f: treat.flavours[modelData] || treat.flavours.vanilla
                readonly property real u: treat.u
                z: index
                y: treat.scoopY(index) * u

                // A round top and a wavy, melting bottom edge.
                Shape {
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: scoop.f.fill
                        strokeColor: treat.rim(scoop.modelData)
                        strokeWidth: Math.max(1, scoop.u * 0.14)
                        joinStyle: ShapePath.RoundJoin
                        PathSvg {
                            path: {
                                const r = treat.r * scoop.u, b = 0.2 * r, s = r / 3
                                return ("M %1 %2 A %3 %3 0 1 1 %4 %2 A %5 %6 0 0 1 %7 %2 "
                                        + "A %5 %6 0 0 1 %8 %2 A %5 %6 0 0 1 %1 %2 Z")
                                    .arg(-r).arg(b).arg(r).arg(r).arg(s).arg(s * 1.05).arg(s).arg(-s)
                            }
                        }
                    }
                }
                // Bits in it: vanilla's specks, chocolate's swirl, strawberry
                // pieces, mint's chips.
                Repeater {
                    model: [[-0.75, -0.55, 25], [0.35, -0.95, -30], [0.7, -0.15, 60], [-0.2, 0.05, -10]]
                    delegate: Rectangle {
                        required property var modelData
                        x: modelData[0] * scoop.u
                        y: modelData[1] * scoop.u
                        width: (scoop.modelData === "vanilla" ? 0.22 : 0.42) * scoop.u
                        height: (scoop.modelData === "vanilla" ? 0.22 : 0.3) * scoop.u
                        radius: width / 3
                        rotation: modelData[2]
                        color: scoop.f.bits
                        opacity: scoop.modelData === "chocolate" ? 0.55 : 0.9
                    }
                }
                // A shine, top left.
                Rectangle {
                    x: -1.05 * scoop.u
                    y: -1.15 * scoop.u
                    width: 0.75 * scoop.u
                    height: 0.4 * scoop.u
                    radius: height / 2
                    rotation: -35
                    color: "white"
                    opacity: 0.55
                }
            }
        }

        // ---- Sprinkles over the top scoop.
        Repeater {
            model: treat.toppings.indexOf("sprinkles") >= 0
                   ? [[-0.95, -0.6, 30, "#E5484D"], [-0.25, -1.15, -40, "#5B8DEF"], [0.55, -0.85, 70, "#F2B84B"],
                      [1.0, -0.25, -20, "#3DB37A"], [-0.55, 0.0, 80, "#8E7CE6"], [0.25, -0.2, 10, "#FFFFFF"],
                      [-1.15, 0.15, -60, "#3DB37A"]]
                   : []
            delegate: Rectangle {
                required property var modelData
                z: treat.count + 0.2
                x: (modelData[0] - 0.24) * treat.u
                y: (treat.topY + modelData[1]) * treat.u
                width: 0.5 * treat.u
                height: Math.max(2, 0.17 * treat.u)
                radius: height / 2
                rotation: modelData[2]
                color: modelData[3]
                border.width: modelData[3] === "#FFFFFF" ? 1 : 0
                border.color: "#D0C8C0"
            }
        }

        // ---- The cherry on top, with its stem.
        Item {
            visible: treat.toppings.indexOf("cherry") >= 0
            z: treat.count + 0.4
            y: (treat.count > 0 ? treat.topY - treat.r - 0.05 : treat.topY + 0.45) * treat.u
            Shape {
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: treat.dark ? "#8FCB6E" : "#4E7D3A"
                    strokeWidth: Math.max(1.5, treat.u * 0.16)
                    capStyle: ShapePath.RoundCap
                    PathSvg {
                        readonly property real u: treat.u
                        path: "M 0 %1 Q %2 %3 %4 %5".arg(-0.45 * u).arg(0.1 * u).arg(-1.1 * u).arg(0.6 * u).arg(-1.25 * u)
                    }
                }
            }
            Rectangle {
                x: -0.58 * treat.u
                y: -0.95 * treat.u
                width: 1.16 * treat.u
                height: width
                radius: width / 2
                color: "#D8263C"
                border.width: Math.max(1, treat.u * 0.1)
                border.color: treat.dark ? "#FF7A88" : "#9E1428"
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
    }
}
