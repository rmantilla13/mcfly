import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.LocalStorage
import McFly
import McFly.Core

// Penguin March: penguins drop from a hatch and walk, and it's up to you to
// get enough of them home to the igloo. Pick a skill, then tap a penguin.
//
// The world (PenguinWorld, C++) runs the level and draws it; this is the
// frame around it: the skills, play and pause, fast-forward, the levels,
// the cards before and after a level. Taps go to the nearest penguin that
// can take the skill, within a finger's reach. The world keeps its shape and
// is scaled to fit the stage; where that would make the penguins too small
// to read across the room, it is scaled up and can be dragged.
//
// The current level and the most penguins saved on each are remembered
// (LocalStorage, one small write per level finished).
Item {
    id: game

    // The level running (tests, and GamesScreen's view of the game).
    readonly property alias world: world
    readonly property int levelCount: world.levelCount
    readonly property int level: world.level
    // Running (Play) or paused.
    property bool playing: false
    property bool fast: false
    // The skill a tap gives.
    property string skill: ""
    // The card before a level has been shown and played past.
    property bool briefed: false
    property bool pickerOpen: false
    // Most penguins saved, by level index.
    property var best: ({})
    // GamesScreen calls it while how to play or the assistant panel covers
    // the game: it waits for Play after.
    function pause() { playing = false }
    readonly property var skills: [
        { key: "block", name: qsTr("Block") },
        { key: "dig", name: qsTr("Dig") },
        { key: "bash", name: qsTr("Bash") },
        { key: "build", name: qsTr("Build") },
        { key: "float", name: qsTr("Float") }
    ]

    // ---- Layout
    // The 7" panel: one row of buttons under the world, the count over its
    // sky. Elsewhere a header above and the skills, named, below.
    readonly property bool slim: height < 420
    readonly property real headerHeight: slim ? 0 : Theme.touchTarget
    readonly property real barHeight: slim ? Theme.touchTarget : 104
    readonly property real gap: Theme.spacing
    readonly property real roomWidth: width
    readonly property real roomHeight: Math.max(0, height - barHeight - gap - (slim ? 0 : headerHeight + gap))
    readonly property size worldSize: world.worldSize
    readonly property real fitZoom: Math.min(roomWidth / worldSize.width, roomHeight / worldSize.height)
    // A penguin is 16 world pixels. The whole level shows where that leaves
    // a penguin 24 pixels tall or more (21 on the 7", where the world is a
    // little taller than the room and drags up and down). The portrait panel
    // is narrow with height to spare: it shows the level 35 pixels a penguin
    // and drags sideways.
    readonly property real zoom: Theme.tall ? Math.max(fitZoom, Math.min(roomHeight / worldSize.height, 2.2))
                                            : Math.max(fitZoom, slim ? 1.3 : 1.5)
    readonly property real viewHeight: Math.min(roomHeight, worldSize.height * zoom)
    // The world and the skills under it, as one block in the middle.
    readonly property real headerBottom: slim ? 0 : headerHeight + gap
    readonly property real blockTop: headerBottom + Math.max(0, (height - headerBottom - viewHeight - gap - barHeight) / 2)

    function stars(saved, need, total) {
        return saved >= total ? 3 : saved >= need + Math.ceil((total - need) / 2) ? 2 : saved >= need ? 1 : 0
    }

    function load(index) {
        world.level = index
        playing = false
        fast = false
        briefed = false
        const left = world.skillsLeft
        const first = skills.find(s => left[s.key] > 0)
        skill = first ? first.key : ""
        remember("level", world.level)
        view.centre()
    }
    function start() {
        briefed = true
        playing = true
    }
    function restart() {
        world.restart(false)
        briefed = true
        playing = true
    }
    function showMe() {
        world.restart(true)
        briefed = true
        playing = true
    }
    function tap(x, y) {
        if (world.tapAt(x, y))
            return
        ripple.show(x, y, Theme.textMuted)
    }

    readonly property bool over: world.finished
    onOverChanged: {
        if (!over)
            return
        playing = false
        if (!world.demo)
            record(world.saved)
    }

    // ---- Progress, in LocalStorage
    function database() {
        try {
            const db = LocalStorage.openDatabaseSync("McFlyPenguinMarch", "1.0", "Penguin March progress", 10000)
            db.transaction(tx => {
                tx.executeSql("CREATE TABLE IF NOT EXISTS best(level INTEGER PRIMARY KEY, saved INTEGER)")
                tx.executeSql("CREATE TABLE IF NOT EXISTS kv(key TEXT PRIMARY KEY, value TEXT)")
            })
            return db
        } catch (e) {
            console.warn("Penguin March: progress is not saved:", e)
            return null
        }
    }
    function restore() {
        const db = database()
        if (!db)
            return 0
        let start = 0
        try {
            db.readTransaction(tx => {
                const rows = tx.executeSql("SELECT level, saved FROM best").rows
                const saved = {}
                for (let i = 0; i < rows.length; ++i)
                    saved[rows.item(i).level] = rows.item(i).saved
                best = saved
                const kept = tx.executeSql("SELECT value FROM kv WHERE key = 'level'").rows
                if (kept.length)
                    start = Number(kept.item(0).value) || 0
            })
        } catch (e) {
            console.warn("Penguin March: could not read progress:", e)
        }
        return start
    }
    function remember(key, value) {
        const db = database()
        if (!db)
            return
        try {
            db.transaction(tx => tx.executeSql("INSERT OR REPLACE INTO kv VALUES (?, ?)", [key, String(value)]))
        } catch (e) {
            console.warn("Penguin March: could not save:", e)
        }
    }
    // Keeps the most saved on this level, if it was a win.
    function record(saved) {
        if (saved < world.need || (best[level] !== undefined && best[level] >= saved))
            return
        const updated = Object.assign({}, best)
        updated[level] = saved
        best = updated
        const db = database()
        if (!db)
            return
        try {
            db.transaction(tx => tx.executeSql("INSERT OR REPLACE INTO best VALUES (?, ?)", [level, saved]))
        } catch (e) {
            console.warn("Penguin March: could not save:", e)
        }
    }

    Component.onCompleted: load(restore())

    // ---- Header: the level and its count, and the controls (not on the 7")
    RowLayout {
        id: header
        visible: !game.slim
        width: parent.width
        height: game.headerHeight
        spacing: 12

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Label {
                Layout.fillWidth: true
                text: qsTr("Level %1 · %2").arg(game.level + 1).arg(world.name)
                color: Theme.text
                font.pixelSize: Theme.fontMd
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                text: game.countLine
                color: Theme.textMuted
                font.pixelSize: Theme.fontSm
                elide: Text.ElideRight
            }
        }
        Item {
            id: headerSlot
            implicitWidth: controls.implicitWidth
            implicitHeight: controls.implicitHeight
        }
    }
    readonly property string countLine: {
        const toCome = world.total - world.released
        let line = qsTr("%1 of %2 home").arg(world.saved).arg(world.need)
        if (world.out > 0)
            line += " · " + qsTr("%1 out").arg(world.out)
        if (toCome > 0 && world.started)
            line += " · " + qsTr("%1 to come").arg(toCome)
        return line
    }

    // The buttons that run the level: play/pause, fast, again, the levels.
    // In the header, or beside the skills on the 7".
    Row {
        id: controls
        parent: game.slim ? barSlot : headerSlot
        anchors.centerIn: parent
        spacing: 8
        IconButton {
            icon: game.playing ? "pause" : "play"
            enabled: !world.finished
            onClicked: game.briefed ? (game.playing = !game.playing) : game.start()
        }
        IconButton {
            icon: "forward"
            kind: game.fast ? "active" : "rest"
            ink: game.fast ? Glass.ink : Theme.text
            enabled: !world.finished
            onClicked: game.fast = !game.fast
        }
        IconButton {
            icon: "refresh"
            onClicked: game.restart()
        }
        IconButton {
            icon: "grid"
            onClicked: { game.playing = false; game.pickerOpen = true }
        }
    }

    // ---- The world
    Item {
        id: stage
        y: game.blockTop
        width: parent.width
        height: game.viewHeight

        Flickable {
            id: view
            width: Math.min(stage.width, world.width)
            height: Math.min(stage.height, world.height)
            anchors.centerIn: parent
            contentWidth: world.width
            contentHeight: world.height
            interactive: contentWidth > width + 1 || contentHeight > height + 1
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            // Where the view pans (portrait, the 7"), it starts on the hatch.
            function centre() {
                contentX = Math.max(0, Math.min(contentWidth - width, world.hatch.x * game.zoom - width / 2))
                contentY = Math.max(0, (contentHeight - height) / 2)
            }
            onWidthChanged: centre()
            onHeightChanged: centre()

            Rectangle {
                width: world.width
                height: world.height
                gradient: Gradient {
                    GradientStop { position: 0; color: Theme.dark ? "#0B1424" : "#B9DCF3" }
                    GradientStop { position: 1; color: Theme.dark ? "#1D2C47" : "#EDF6FC" }
                }
            }
            PenguinWorld {
                id: world
                width: game.worldSize.width * game.zoom
                height: game.worldSize.height * game.zoom
                running: game.playing && !game.pickerOpen
                speed: game.fast ? 3 : 1
                skill: game.skill
                dark: Theme.dark
                reach: 72
                onAssigned: (key, x, y) => ripple.show(x, y, world.skillColor(key))

                TapHandler {
                    enabled: game.briefed && !world.finished && !world.demo
                    onTapped: eventPoint => game.tap(eventPoint.position.x, eventPoint.position.y)
                }
                // Where a tap landed: a ring in the skill's colour, or grey
                // if no penguin there could take it.
                Rectangle {
                    id: ripple
                    property real cx: 0
                    property real cy: 0
                    property real r: 0
                    function show(x, y, tint) {
                        cx = x
                        cy = y
                        border.color = tint
                        rippleAnim.restart()
                    }
                    x: cx - r
                    y: cy - r
                    width: 2 * r
                    height: 2 * r
                    radius: r
                    color: "transparent"
                    border.width: 4
                    opacity: 0
                    ParallelAnimation {
                        id: rippleAnim
                        NumberAnimation { target: ripple; property: "r"; from: 12; to: 40; duration: 360; easing.type: Easing.OutCubic }
                        NumberAnimation { target: ripple; property: "opacity"; from: 0.95; to: 0; duration: 360 }
                    }
                }
            }
        }
        // Round the view's corners by painting the page colour over them.
        Rectangle {
            anchors.fill: view
            anchors.margins: -Theme.radiusSm
            radius: Theme.radiusSm * 2
            color: "transparent"
            border.width: Theme.radiusSm
            border.color: Theme.background
        }

        // Finish, once enough are home and the rest can't be (or needn't);
        // a way through, once the skills are spent and they aren't.
        PillButton {
            anchors.right: view.right
            anchors.top: view.top
            anchors.margins: 10
            readonly property bool enough: world.saved >= world.need
            readonly property bool spent: game.skills.every(s => !world.skillsLeft[s.key])
            visible: world.started && !world.finished && !world.demo && (enough ? world.out > 0 : spent)
            text: enough ? qsTr("Finish") : qsTr("Show me")
            fill: enough ? Glass.primary : Theme.surface
            ink: enough ? "white" : Theme.text
            onClicked: enough ? world.finish() : game.showMe()
        }

        // Where the view pans (portrait): which way the igloo is, while it's
        // out of sight. Tapping it pans there.
        Rectangle {
            id: pointer
            readonly property real door: world.igloo.x * game.zoom - view.contentX
            readonly property bool onRight: door > view.width
            visible: view.interactive && (onRight || door < 0) && !world.finished
            x: onRight ? view.x + view.width - width - 10 : view.x + 10
            y: view.y + Math.max(10, Math.min(view.height - height - 10, world.igloo.y * game.zoom - view.contentY - height))
            width: pointerRow.implicitWidth + 20
            height: Theme.touchTarget
            radius: height / 2
            color: Theme.surface
            opacity: 0.94
            Row {
                id: pointerRow
                anchors.centerIn: parent
                spacing: 4
                layoutDirection: pointer.onRight ? Qt.LeftToRight : Qt.RightToLeft
                PenguinPicture {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 36
                    kind: "igloo"
                    dark: Theme.dark
                }
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: pointer.onRight ? "right" : "left"
                    color: Theme.text
                }
            }
            TapHandler {
                onTapped: {
                    panTo.to = Math.max(0, Math.min(view.contentWidth - view.width,
                                                    world.igloo.x * game.zoom - view.width / 2))
                    panTo.restart()
                }
            }
            NumberAnimation { id: panTo; target: view; property: "contentX"; duration: Theme.glide; easing.type: Easing.InOutCubic }
        }

        // ---- Before a level: what it asks, and what's new.
        Card {
            visible: !game.briefed && !world.demo
            slim: game.slim
            anchors.centerIn: view
            width: Math.min(view.width - 24, 520)
            height: Math.min(view.height - 16, implicitHeight)
            Label {
                Layout.fillWidth: true
                visible: !game.slim
                text: qsTr("Level %1 of %2").arg(game.level + 1).arg(game.levelCount)
                color: Theme.textMuted
                font.pixelSize: Theme.fontXs
                horizontalAlignment: Text.AlignHCenter
            }
            Label {
                Layout.fillWidth: true
                text: game.slim ? qsTr("%1 · %2").arg(game.level + 1).arg(world.name) : world.name
                color: Theme.text
                font.pixelSize: game.slim ? Theme.fontMd : Theme.fontLg
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                text: qsTr("Get %1 of %2 penguins home.").arg(world.need).arg(world.total)
                      + (game.slim ? " " + world.hint : "")
                color: Theme.text
                font.pixelSize: game.slim ? Theme.fontXs : Theme.fontSm
                font.weight: Font.Medium
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
            Label {
                Layout.fillWidth: true
                visible: !game.slim
                text: world.hint
                color: Theme.textMuted
                font.pixelSize: Theme.fontSm
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
            PillButton {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                text: qsTr("Play")
                onClicked: game.start()
            }
        }

        // ---- After: how many made it.
        Card {
            id: result
            visible: world.finished
            slim: game.slim
            anchors.centerIn: view
            width: Math.min(view.width - 24, 520)
            height: Math.min(view.height - 16, implicitHeight)
            readonly property int count: game.stars(world.saved, world.need, world.total)
            Label {
                Layout.alignment: Qt.AlignHCenter
                visible: world.won
                text: "★".repeat(result.count) + "☆".repeat(3 - result.count)
                color: Theme.warning
                font.pixelSize: game.slim ? 30 : 40
            }
            Label {
                Layout.fillWidth: true
                text: world.won ? qsTr("%1 of %2 home!").arg(world.saved).arg(world.total)
                                : qsTr("%1 of %2 home").arg(world.saved).arg(world.total)
                color: Theme.text
                font.pixelSize: Theme.fontLg
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
            }
            Label {
                Layout.fillWidth: true
                text: world.demo ? qsTr("That's one way. Your turn.")
                    : world.won ? (world.saved >= world.total ? qsTr("Every one of them.") : qsTr("You needed %1.").arg(world.need))
                    : qsTr("It takes %1. Try again, or see a way through.").arg(world.need)
                color: Theme.textMuted
                font.pixelSize: Theme.fontSm
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                spacing: 12
                PillButton {
                    visible: !world.won && !world.demo
                    text: qsTr("Show me")
                    fill: Theme.surfaceAlt
                    ink: Theme.text
                    onClicked: game.showMe()
                }
                PillButton {
                    text: world.won && !world.demo ? qsTr("Play again") : qsTr("Try again")
                    fill: world.won && !world.demo ? Theme.surfaceAlt : Glass.primary
                    ink: world.won && !world.demo ? Theme.text : "white"
                    onClicked: world.demo ? game.load(game.level) : game.restart()
                }
                PillButton {
                    visible: world.won && !world.demo
                    text: game.level + 1 < game.levelCount ? qsTr("Next level") : qsTr("All levels")
                    onClicked: game.level + 1 < game.levelCount ? game.load(game.level + 1) : (game.pickerOpen = true)
                }
            }
        }
    }

    // A card over the middle of the world.
    component Card: Rectangle {
        default property alias content: column.data
        property bool slim: false
        implicitHeight: column.implicitHeight + (slim ? 28 : 48)
        radius: Theme.radius
        color: Theme.surface
        border.width: 1
        border.color: Theme.divider
        // Keep taps from reaching the world underneath.
        MouseArea { anchors.fill: parent }
        ColumnLayout {
            id: column
            anchors.centerIn: parent
            width: parent.width - (parent.slim ? 32 : 48)
            spacing: parent.slim ? 4 : 10
        }
    }

    // ---- Skills (and on the 7", the controls beside them)
    RowLayout {
        id: bar
        y: game.blockTop + game.viewHeight + game.gap
        anchors.horizontalCenter: parent.horizontalCenter
        height: game.barHeight
        spacing: game.slim ? 8 : 12

        // The count, on the 7" (elsewhere it's in the header).
        ColumnLayout {
            visible: game.slim
            Layout.preferredWidth: 96
            Layout.rightMargin: 4
            spacing: 0
            Label {
                text: qsTr("Home %1/%2").arg(world.saved).arg(world.need)
                color: Theme.text
                font.pixelSize: Theme.fontSm
                font.weight: Font.DemiBold
            }
            Label {
                text: qsTr("Level %1").arg(game.level + 1)
                color: Theme.textMuted
                font.pixelSize: Theme.fontXs
            }
        }

        // Showing a way through: in place of the skills, which it doesn't take.
        Label {
            visible: world.demo
            text: qsTr("Showing a way through")
            color: Theme.text
            font.pixelSize: Theme.fontSm
            font.weight: Font.Medium
        }
        PillButton {
            visible: world.demo
            text: qsTr("Stop")
            fill: Theme.surface
            ink: Theme.text
            onClicked: game.load(game.level)
        }
        Repeater {
            model: game.skills
            delegate: Item {
                id: button
                required property var modelData
                visible: !world.demo
                readonly property int remaining: world.skillsLeft[modelData.key] || 0
                readonly property bool chosen: game.skill === modelData.key
                implicitWidth: game.slim ? Theme.touchTarget : Math.min(112, (game.width - 4 * 12) / 5)
                implicitHeight: game.barHeight
                opacity: remaining > 0 ? 1 : 0.4
                scale: tap.pressed ? 0.94 : 1
                Behavior on scale { NumberAnimation { duration: Theme.quick } }

                Lens {
                    anchors.fill: parent
                    kind: button.chosen ? "active" : "rest"
                    fill: Theme.surface
                    radius: Theme.radiusSm
                }
                PenguinPicture {
                    x: (parent.width - width) / 2
                    y: game.slim ? 2 : 6
                    width: game.slim ? 56 : 64
                    height: width
                    kind: button.modelData.key
                    dark: Theme.dark
                }
                Label {
                    visible: !game.slim
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    text: button.modelData.name
                    color: button.chosen ? Glass.ink : Theme.text
                    font.pixelSize: Theme.fontSm
                    font.weight: Font.Medium
                }
                // How many are left, in the skill's colour.
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: game.slim ? -4 : 6
                    width: Math.max(height, countLabel.implicitWidth + 12)
                    height: game.slim ? 24 : 28
                    radius: height / 2
                    color: button.remaining > 0 ? world.skillColor(button.modelData.key) : Theme.textMuted
                    Label {
                        id: countLabel
                        anchors.centerIn: parent
                        text: button.remaining
                        color: "white"
                        font.pixelSize: Theme.fontXs
                        font.weight: Font.Bold
                    }
                }
                TapHandler {
                    id: tap
                    enabled: button.remaining > 0
                    onTapped: game.skill = button.modelData.key
                }
            }
        }
        Item {
            id: barSlot
            visible: game.slim
            Layout.leftMargin: 8
            implicitWidth: controls.implicitWidth
            implicitHeight: controls.implicitHeight
        }
    }

    // ---- Level picker
    Rectangle {
        anchors.fill: parent
        z: 10
        color: Theme.background
        opacity: game.pickerOpen ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.smooth } }
        // Keep taps from reaching the world underneath.
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.spacing

            RowLayout {
                Layout.fillWidth: true
                Label {
                    Layout.fillWidth: true
                    text: qsTr("Choose a level")
                    color: Theme.text
                    font.pixelSize: Theme.fontLg
                    font.weight: Font.DemiBold
                }
                Label {
                    text: qsTr("%1 of %2 won").arg(Object.keys(game.best).length).arg(game.levelCount)
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSm
                }
                IconButton { icon: "close"; onClicked: game.pickerOpen = false }
            }

            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                readonly property int columns: Math.max(4, Math.floor(width / 150))
                cellWidth: width / columns
                cellHeight: Math.min(Math.max(cellWidth * 0.8, Theme.touchTarget + 12), 130)
                model: game.levelCount
                delegate: Item {
                    id: tile
                    required property int index
                    readonly property var info: world.info(index)
                    readonly property bool won: game.best[index] !== undefined
                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 6
                        radius: Theme.radiusSm
                        color: tile.won ? Theme.accentSoft : Theme.surface
                        border.width: tile.index === game.level ? 3 : 0
                        border.color: Theme.accent
                        scale: levelTap.pressed ? 0.95 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.quick } }

                        ColumnLayout {
                            anchors.centerIn: parent
                            width: parent.width - 16
                            spacing: 2
                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                text: tile.index + 1
                                color: Theme.text
                                font.pixelSize: Theme.fontMd
                                font.weight: Font.DemiBold
                            }
                            Label {
                                Layout.fillWidth: true
                                visible: grid.cellHeight >= 96
                                text: tile.info.name
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontXs
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                text: tile.won ? "★".repeat(game.stars(game.best[tile.index], tile.info.need, tile.info.total)) : " "
                                color: Theme.warning
                                font.pixelSize: 13
                            }
                        }
                        TapHandler {
                            id: levelTap
                            onTapped: {
                                game.pickerOpen = false
                                game.load(tile.index)
                            }
                        }
                    }
                }
            }
        }
    }
}
