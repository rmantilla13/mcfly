import QtQuick
import QtQuick.Controls
import McFly

// The assistant's suggestions as chips, in rows no wider than the item:
// centred and split evenly (the Ask screen: four make two and two), or flush
// left and packed in order, keeping what fits in `maxRows` (Home, over the
// ask bar). A Flow can't do either: it leaves every row flush left.
//
//   SuggestionChips { width: …; items: AI.suggestions; onPicked: text => … }
Column {
    id: chips
    property var items: []
    property bool centred: true
    property int maxRows: 0   // 0: as many rows as it takes
    signal picked(string text)

    readonly property int chipHeight: 52
    readonly property int gap: 10
    spacing: 12

    FontMetrics { id: metrics; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSm - 1 }
    function chipWidth(text) { return Math.ceil(metrics.advanceWidth(text)) + 36 }
    function rowWidth(row) { return row.reduce((sum, text) => sum + chipWidth(text), 0) + (row.length - 1) * gap }

    readonly property var rows: {
        const list = Array.from(items || [])
        if (width <= 0 || list.length === 0)
            return []
        if (centred) {
            for (let count = 1; count < list.length; ++count) {
                const per = Math.ceil(list.length / count)
                const split = []
                for (let i = 0; i < list.length; i += per)
                    split.push(list.slice(i, i + per))
                if (split.every(row => rowWidth(row) <= width))
                    return split
            }
            return list.map(text => [text])
        }
        const packed = []
        for (const text of list) {
            const last = packed[packed.length - 1]
            if (last && rowWidth(last.concat([text])) <= width)
                last.push(text)
            else if (chipWidth(text) <= width && (maxRows <= 0 || packed.length < maxRows))
                packed.push([text])
        }
        return packed
    }

    Repeater {
        model: chips.rows
        delegate: Row {
            required property var modelData
            anchors.horizontalCenter: chips.centred ? parent.horizontalCenter : undefined
            spacing: chips.gap
            Repeater {
                model: modelData
                delegate: Rectangle {
                    required property string modelData
                    width: label.implicitWidth + 36
                    height: chips.chipHeight
                    radius: height / 2
                    color: Theme.surface
                    border.color: Theme.divider
                    Label { id: label; anchors.centerIn: parent; text: modelData; color: Theme.text; font.pixelSize: Theme.fontSm - 1 }
                    // Shorter than a touch target; the hit area is not.
                    TapHandler { margin: (Theme.touchTarget - chips.chipHeight) / 2; onTapped: chips.picked(modelData) }
                }
            }
        }
    }
}
