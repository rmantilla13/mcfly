import QtQuick
import McFly
import McFly.Core

// A screen's contents settling in as it shows: `value` runs 0 → 1 over
// Theme.revealDuration each time `shown` turns true, and at(i) is item i's
// share of it, eased and a little later than the one before (capped, so a
// long list doesn't keep arriving). A screen feeds it `isCurrent` (picked),
// not `shown` (picked and not under the assistant panel), so closing the
// panel doesn't play the page's arrival again. The rows bind to it:
//
//   Reveal { id: rv; shown: screen.isCurrent }
//   delegate: Item { opacity: rv.at(index); transform: Translate { y: rv.rise(index) } }
//
// A delegate made later (a sync rebuilds them all every minute) reads 1 and
// is simply there; nothing replays from a delegate's onCompleted. Off with
// Settings → Animated tiles: everything is in place at once.
Item {
    id: reveal
    property bool shown: true
    property real value: 1
    // How far an item travels up as it arrives.
    property real distance: 14

    visible: false
    width: 0
    height: 0

    // Each item fades in over Theme.enter; the last (index `cap` and on)
    // starts in time to land at revealDuration.
    readonly property int cap: 7
    readonly property real _span: Theme.enter / Theme.revealDuration
    readonly property real _step: (1 - _span) / cap

    function at(i) {
        const t = Math.max(0, Math.min(1, (value - Math.min(Math.max(0, i), cap) * _step) / _span))
        return 1 - Math.pow(1 - t, 3)
    }
    function rise(i) { return (1 - at(i)) * distance }

    // Drawn in software (no GPU: a fallback, and the offscreen pictures),
    // moving whole pages each frame costs too much and smears: no entrance.
    readonly property bool animates: Device.animatedTiles && GraphicsInfo.api !== GraphicsInfo.Software
    function play() {
        if (animates)
            anim.restart()
        else
            value = 1
    }
    onShownChanged: if (shown) play()
    // Shown from the start (the screen the app opens on): it settles in too.
    Component.onCompleted: if (shown) play()
    // The renderer is only known once the item is in a window.
    onAnimatesChanged: if (!animates) { anim.stop(); value = 1 }

    NumberAnimation {
        id: anim
        target: reveal
        property: "value"
        from: 0
        to: 1
        duration: Theme.revealDuration
    }
}
