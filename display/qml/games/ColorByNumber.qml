import QtQuick
import QtQuick.Controls
import QtQuick.LocalStorage
import McFly
import McFly.Core

// Color by Number: pick a picture, pick a colour, and fill in every cell
// with its number. Written for McFly, after Araib Karim's Color by Number
// for iOS (none of its code or pictures is used; the pictures are ours, in
// src/games/ColorByNumber.cpp).
//
// The cells are smaller than a fingertip, so painting forgives: only cells
// with the chosen number take its colour, and a sweep fills every cell it
// crosses. One finger does both jobs: a drag that starts on a cell of the
// chosen number paints, a drag from anywhere else moves the picture, and a
// tap on another number's cell picks that colour. − and + zoom (so does a
// pinch, where the panel has two fingers to give).
//
// Every picture's progress is kept in LocalStorage as you go, and when the
// game closes.
Item {
    id: game

    // "gallery" or "paint"
    property string view: "gallery"
    // Each picture's progress (ColorByNumberBoard.saved), by its id.
    property var progress: ({})
    readonly property real gap: Theme.spacing
    // Wide and short (the 7" panel, a TV): the picture on the left, the
    // controls beside it. Otherwise the controls under the picture.
    readonly property bool side: width >= height + 300 + gap

    // ---- Progress, in LocalStorage
    function database() {
        try {
            const db = LocalStorage.openDatabaseSync("McFlyColorByNumber", "1.0", "Color by Number progress", 100000)
            db.transaction(tx => tx.executeSql("CREATE TABLE IF NOT EXISTS pictures(id TEXT PRIMARY KEY, saved TEXT)"))
            return db
        } catch (e) {
            console.warn("Color by Number: progress is not saved:", e)
            return null
        }
    }
    function restore() {
        const db = database()
        if (!db)
            return
        try {
            db.readTransaction(tx => {
                const rows = tx.executeSql("SELECT id, saved FROM pictures").rows
                const all = {}
                for (let i = 0; i < rows.length; ++i)
                    all[rows.item(i).id] = rows.item(i).saved
                progress = all
            })
        } catch (e) {
            console.warn("Color by Number: could not read progress:", e)
        }
    }
    // The picture being painted, to the table and to the gallery.
    function save() {
        if (view !== "paint")
            return
        const id = board.pictureId, saved = board.saved
        if (progress[id] === saved)
            return
        const all = Object.assign({}, progress)
        all[id] = saved
        progress = all
        const db = database()
        if (!db)
            return
        try {
            db.transaction(tx => tx.executeSql("INSERT OR REPLACE INTO pictures(id, saved) VALUES(?, ?)", [id, saved]))
        } catch (e) {
            console.warn("Color by Number: could not save:", e)
        }
    }
    function open(index) {
        save()
        board.picture = index
        board.saved = progress[board.pictureId] || ""
        view = "paint"
    }
    function showGallery() {
        save()
        view = "gallery"
    }
    function openNext() {
        open((board.picture + 1) % board.pictureCount)
    }
    // How much of a saved picture is done, 0 to 1.
    function share(saved) {
        if (!saved)
            return 0
        let ones = 0
        for (let i = 0; i < saved.length; ++i)
            ones += saved[i] === "1" ? 1 : 0
        return ones / saved.length
    }
    Component.onCompleted: restore()
    Component.onDestruction: save()

    // ---- The pictures to choose from
    Item {
        id: gallery
        anchors.fill: parent
        visible: game.view === "gallery"

        Label {
            id: galleryTitle
            width: parent.width
            text: qsTr("Pick a picture")
            color: Theme.text
            font.pixelSize: Theme.fontLg
            font.weight: Font.DemiBold
        }
        Flickable {
            id: shelf
            y: galleryTitle.height + game.gap
            width: parent.width
            height: parent.height - y
            clip: true
            contentHeight: shelfGrid.height
            boundsBehavior: Flickable.StopAtBounds

            Grid {
                id: shelfGrid
                readonly property int cardWidth: (shelf.width - (columns - 1) * spacing) / columns
                columns: Math.max(2, Math.floor((shelf.width + spacing) / ((Theme.mini ? 170 : 220) + spacing)))
                spacing: game.gap

                Repeater {
                    model: board.pictureCount
                    delegate: Rectangle {
                        id: card
                        required property int index
                        readonly property real done: game.share(game.progress[thumb.pictureId])
                        objectName: "picture:" + index
                        width: shelfGrid.cardWidth
                        height: Math.round(width * 0.72) + 52
                        radius: Theme.radius
                        color: Theme.surface
                        scale: cardTap.pressed ? 0.97 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.quick } }

                        Rectangle {
                            id: frame
                            x: 8
                            y: 8
                            width: parent.width - 16
                            height: Math.round(card.width * 0.72) - 8
                            radius: Theme.radiusSm
                            color: Theme.dark ? Theme.background : Theme.sunken
                            ColorByNumberBoard {
                                id: thumb
                                anchors.fill: parent
                                anchors.margins: 10
                                picture: card.index
                                preview: true
                                dark: Theme.dark
                                saved: game.progress[pictureId] || ""
                            }
                        }
                        Label {
                            x: 14
                            y: frame.y + frame.height + 8
                            width: parent.width - 28 - status.width
                            text: thumb.title
                            color: Theme.text
                            font.pixelSize: Theme.fontSm
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Label {
                            id: status
                            x: parent.width - 14 - width
                            y: frame.y + frame.height + 8
                            text: card.done >= 1 ? qsTr("Done") : card.done > 0 ? qsTr("%1%").arg(Math.floor(card.done * 100)) : ""
                            color: card.done >= 1 ? Theme.success : Theme.textMuted
                            font.pixelSize: Theme.fontSm
                            font.weight: Font.DemiBold
                        }
                        TapHandler { id: cardTap; onTapped: game.open(card.index) }
                    }
                }
            }
        }
    }

    // ---- Painting a picture
    Item {
        id: easel
        anchors.fill: parent
        visible: game.view === "paint"

        Rectangle {
            id: canvas
            x: 0
            y: 0
            width: game.side ? Math.min(game.height, game.width - 300 - game.gap) : game.width
            height: game.side ? game.height : Math.max(0, game.height - 64 - game.gap - 64 - game.gap)
            radius: Theme.radius
            color: Theme.dark ? Theme.surface : Theme.sunken
            clip: true

            ColorByNumberBoard {
                id: board
                objectName: "board"
                anchors.fill: parent
                anchors.margins: 8
                dark: Theme.dark
                onFinished: {
                    fit()
                    game.save()
                }
            }
            // One finger: paint from a cell of the chosen number, move the
            // picture from anywhere else, pick a colour with a tap.
            MouseArea {
                id: touch
                property point last
                property bool painting: false
                property bool moved: false
                anchors.fill: board
                onPressed: mouse => {
                    last = Qt.point(mouse.x, mouse.y)
                    moved = false
                    const n = board.numberAt(last)
                    painting = n > 0 && n === board.selected
                    if (painting)
                        board.paintAt(last)
                }
                onPositionChanged: mouse => {
                    const p = Qt.point(mouse.x, mouse.y)
                    // A finger wobbles: a tap stays a tap until it travels.
                    if (!moved && Math.hypot(p.x - last.x, p.y - last.y) < Qt.styleHints.startDragDistance)
                        return
                    moved = true
                    if (painting)
                        board.paintLine(last, p)
                    else
                        board.panBy(p.x - last.x, p.y - last.y)
                    last = p
                }
                onReleased: mouse => {
                    if (!painting && !moved) {
                        const n = board.numberAt(Qt.point(mouse.x, mouse.y))
                        if (n > 0 && board.colors[n - 1].remaining > 0)
                            board.selected = n
                    }
                    game.save()
                }
            }
            PinchHandler {
                property real lastScale: 1
                target: null
                onActiveChanged: lastScale = 1
                onActiveScaleChanged: {
                    const at = canvas.mapToItem(board, centroid.position.x, centroid.position.y)
                    board.zoomBy(activeScale / lastScale, at)
                    lastScale = activeScale
                }
            }
            WheelHandler {
                onWheel: event => {
                    const at = canvas.mapToItem(board, event.x, event.y)
                    board.zoomBy(event.angleDelta.y > 0 ? 1.15 : 1 / 1.15, at)
                }
            }
        }

        // The controls: beside the picture, or under it.
        Item {
            id: panel
            x: game.side ? canvas.width + game.gap : 0
            y: game.side ? 0 : canvas.height + game.gap
            width: game.width - x
            height: game.height - y

            Row {
                id: tools
                spacing: 12
                IconButton { objectName: "tap:gallery"; icon: "grid"; onClicked: game.showGallery() }
                IconButton {
                    objectName: "tap:zoomout"
                    icon: "minus"
                    enabled: board.canZoomOut
                    onClicked: board.zoomOut()
                }
                IconButton {
                    objectName: "tap:zoomin"
                    icon: "plus"
                    enabled: board.canZoomIn
                    onClicked: board.zoomIn()
                }
                IconButton {
                    objectName: "tap:fit"
                    icon: "photo" // the whole picture
                    enabled: board.canZoomOut
                    onClicked: board.fit()
                }
            }
            Label {
                id: caption
                x: game.side ? 0 : tools.width + game.gap
                y: game.side ? tools.height + game.gap : (tools.height - height) / 2
                width: game.side ? panel.width : panel.width - x
                text: board.done ? board.title
                                 : qsTr("%1 · %2%").arg(board.title).arg(Math.floor(100 * board.painted / Math.max(1, board.total)))
                color: Theme.text
                font.pixelSize: Theme.fontMd
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            // The colours: tap one, and its cells light up on the picture.
            Flow {
                id: swatches
                visible: !board.done
                y: game.side ? caption.y + caption.height + game.gap : tools.height + game.gap
                width: panel.width
                spacing: 8
                Repeater {
                    model: board.colors
                    delegate: Rectangle {
                        id: swatch
                        required property var modelData
                        readonly property bool chosen: board.selected === modelData.number
                        readonly property bool finished: modelData.remaining === 0
                        objectName: "tap:swatch"
                        width: 64
                        height: 64
                        radius: Theme.radiusSm
                        color: modelData.color
                        border.width: 1
                        border.color: Theme.divider
                        opacity: finished ? 0.35 : 1
                        scale: swatchTap.pressed ? 0.94 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.quick } }
                        // The chosen colour: a ring around it.
                        Rectangle {
                            visible: swatch.chosen
                            anchors.fill: parent
                            anchors.margins: -4
                            radius: Theme.radiusSm + 4
                            color: "transparent"
                            border.width: 3
                            border.color: Theme.text
                        }
                        Label {
                            visible: !swatch.finished
                            anchors.centerIn: parent
                            text: swatch.modelData.number
                            color: swatch.modelData.ink
                            font.pixelSize: Theme.fontMd
                            font.weight: Font.DemiBold
                        }
                        Icon {
                            visible: swatch.finished
                            anchors.centerIn: parent
                            name: "check"
                            size: 24
                            color: swatch.modelData.ink
                        }
                        TapHandler {
                            id: swatchTap
                            enabled: !swatch.finished
                            onTapped: board.selected = swatch.modelData.number
                        }
                    }
                }
            }

            // Finished: on to the next picture, or back to them all.
            Flow {
                id: doneRow
                visible: board.done
                y: swatches.y
                width: panel.width
                spacing: 12
                Label {
                    height: 64
                    verticalAlignment: Text.AlignVCenter
                    text: qsTr("Finished!")
                    color: Theme.success
                    font.pixelSize: Theme.fontLg
                    font.weight: Font.DemiBold
                }
                PillButton {
                    objectName: "tap:next"
                    text: qsTr("Next picture")
                    onClicked: game.openNext()
                }
                PillButton {
                    objectName: "tap:all"
                    text: qsTr("All pictures")
                    fill: Theme.surface
                    ink: Theme.text
                    onClicked: game.showGallery()
                }
            }
        }
    }
}
