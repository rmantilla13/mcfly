import QtQuick
import QtQuick.Shapes

// A playing-card suit, drawn for McFly as a path in a 100 × 100 box and
// scaled to fit the item: 0 spades, 1 hearts, 2 diamonds, 3 clubs.
Item {
    id: mark
    property int suit: 0
    property color color: "black"

    readonly property var paths: [
        // Spades: a leaf on a flared stem.
        "M50 4C38 24 6 38 6 60C6 74 16 83 28 83C37 83 44 79 47 72C46 84 42 91 33 96L67 96C58 91 54 84 53 72C56 79 63 83 72 83C84 83 94 74 94 60C94 38 62 24 50 4Z",
        // Hearts.
        "M50 92C22 70 4 52 4 32C4 16 16 6 29 6C38 6 46 11 50 20C54 11 62 6 71 6C84 6 96 16 96 32C96 52 78 70 50 92Z",
        // Diamonds, the sides drawn in a little.
        "M50 3C62 22 74 36 90 50C74 64 62 78 50 97C38 78 26 64 10 50C26 36 38 22 50 3Z",
        // Clubs: three discs, the space between them, and the stem, all
        // wound the same way so the overlaps fill.
        "M29 30a21 21 0 1 0 42 0a21 21 0 1 0-42 0Z M6 58a21 21 0 1 0 42 0a21 21 0 1 0-42 0Z M52 58a21 21 0 1 0 42 0a21 21 0 1 0-42 0Z M40 44L40 66L60 66L60 44Z M46 60C46 78 42 89 32 96L68 96C58 89 54 78 54 60Z"
    ]

    Item {
        readonly property real fit: Math.min(mark.width, mark.height) / 100
        x: (mark.width - 100 * fit) / 2
        y: (mark.height - 100 * fit) / 2
        width: 100
        height: 100
        scale: fit
        transformOrigin: Item.TopLeft
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                strokeColor: "transparent"
                fillColor: mark.color
                fillRule: ShapePath.WindingFill
                PathSvg { path: mark.paths[mark.suit] || mark.paths[0] }
            }
        }
    }
}
