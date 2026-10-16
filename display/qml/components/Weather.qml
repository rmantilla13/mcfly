import QtQuick
import QtQuick.Shapes
import McFly
import McFly.Core

// Weather over a screen saver's backdrop (Settings → Backdrop → Weather,
// Device.weather): snow, petals, fireflies or leaves, the season's where the
// display is or one all year (DisplayController::weatherFor). Decorative:
// it lies between the backdrop and the words, and nothing in it is touched.
//
//   Weather {
//       anchors.fill: parent
//       darkness: ambient.dusk      // or leave it to follow Theme.dark
//   }
//
// Each one is a small item (a dot, a glow, a petal or a leaf drawn as a
// Shape in the mood's glow colours) that the clock moves: snow drifts down
// swaying, petals blow across turning over, leaves rock down like a
// pendulum, fireflies wander the lower part of the screen glowing and
// dimming. How many is DisplayController::weatherCount, the console's and
// the app's numbers: a few dozen at most.
//
// It moves on the same wall-clock slots of 1/maxFps s as Backdrop and
// GradientTile, so a saver's layers change on the same frames and the
// render loop sleeps in between (Theme.saverFps, 10 a second). The clock
// only ticks while it can be seen, Settings → Animated tiles is on and the
// panel is on; nothing at all is built while the weather is off.
Item {
    id: weather

    // ---- What
    property string kind: Device.weatherKind   // "" | snow | petals | fireflies | leaves
    // How far into the night look, 0..1: the colours brighten for a dark
    // canvas. Bind it to the saver's dusk to come in with it.
    property real darkness: Theme.dark ? 1 : 0

    // ---- Motion
    property bool animated: Device.animatedTiles
    property bool active: true                  // false while its page isn't showing
    property bool whileIdle: true               // a screen saver's weather keeps going while idle
    property int maxFps: Theme.saverFps

    readonly property int count: kind === "" ? 0 : Device.weatherCount(kind, width, height)
    readonly property bool playing: count > 0 && animated && active && visible
                                    && (whileIdle ? !Device.screenOff : !Device.idle)
                                    && width > 0 && height > 0 && _windowShown

    // ------------------------------------------------------------------
    // Colours: the mood's glows (the backdrop's own), brightened toward
    // white for a dark canvas.

    readonly property real _dk: Math.max(0, Math.min(1, darkness))
    function _mix(a, b, t) {
        const x = Qt.lighter(a, 1.0), y = Qt.lighter(b, 1.0)   // accepts colours and strings
        return Qt.rgba(x.r + (y.r - x.r) * t, x.g + (y.g - x.g) * t, x.b + (y.b - x.b) * t, x.a + (y.a - x.a) * t)
    }
    function _lift(c, day, night) { return _mix(c, "#FFFFFF", day + (night - day) * _dk) }
    // Snow: a cool grey by day, so it shows on the pale canvas; near white at night.
    readonly property color snow: _mix(_mix(Theme.glowBlue, Theme.textMuted, 0.55), _mix("#FFFFFF", Theme.glowBlue, 0.1), _dk)
    readonly property var petals: [_lift(Theme.glowCoral, 0.05, 0.4), _lift(Theme.glowCoral, 0.3, 0.6), _mix(Theme.glowCoral, Theme.glowCream, 0.55)]
    readonly property var leaves: [Theme.glowCoral, Theme.glowAmber, _mix(Theme.glowCoral, Theme.glowAmber, 0.5),
                                   _mix(Theme.glowAmber, Theme.glowCream, 0.4)].map(c => _lift(c, 0, 0.25))
    readonly property var flies: [_lift(Theme.glowAmber, 0.1, 0.45), _lift(Theme.glowCream, 0.0, 0.4)]

    // ------------------------------------------------------------------
    // Each one's state, kept out of bindings: a plain array the clock
    // steps and copies onto the items. Sizes and speeds are shares of the
    // screen, so a 800×480 panel and a 1920×1200 one look alike.

    property var _ps: []
    readonly property real _u: Math.max(0.6, Math.min(1.8, Math.min(width, height) / 900))
    function _r(lo, hi) { return lo + Math.random() * (hi - lo) }

    // A new one: anywhere on screen when the weather first shows (it is
    // already falling), from above the top later.
    function _make(i, anywhere) {
        const w = width, h = height, u = _u
        const p = { t: _r(0, 100), age: 0 }
        if (kind === "snow") {
            const z = Math.random()                            // nearer: bigger, faster, brighter
            p.size = (4 + z * 8) * u
            p.alpha = 0.45 + z * 0.5
            p.v = h / (24 - z * 12)
            p.sway = (4 + z * 16) * u; p.w = _r(1.3, 2.6); p.ph = _r(0, 6.3)
        } else if (kind === "petals") {
            p.size = _r(24, 38) * u
            p.alpha = _r(0.8, 0.95)
            p.v = h / _r(18, 28)
            p.sway = _r(20, 50) * u; p.w = _r(1.2, 2.4); p.ph = _r(0, 6.3)
            p.rot = _r(0, 360); p.spin = _r(-90, 90)
            p.fw = _r(1.6, 3.4); p.fph = _r(0, 6.3)
        } else if (kind === "leaves") {
            p.size = _r(36, 56) * u
            p.alpha = _r(0.85, 0.97)
            p.v = h / _r(14, 22)
            p.sway = _r(36, 90) * u; p.w = _r(1.5, 2.6); p.ph = _r(0, 6.3)
            p.base = _r(0, 360); p.tilt = _r(25, 60)
            p.fw = _r(1.8, 3.6); p.fph = _r(0, 6.3)
        } else {                                               // fireflies, in the lower part
            p.size = _r(36, 60) * u
            p.cx = _r(0.05, 0.95) * w; p.cy = _r(0.35, 0.9) * h
            p.ax = _r(30, 90) * u; p.ay = _r(20, 60) * u
            p.wx = _r(0.12, 0.3); p.wy = _r(0.15, 0.35); p.phx = _r(0, 6.3); p.phy = _r(0, 6.3)
            p.gw = _r(0.9, 2.0); p.gph = _r(0, 6.3)
            p.tone = i % 2
            return p
        }
        p.tone = i % (kind === "leaves" ? 4 : kind === "petals" ? 3 : 1)
        // The wind: one way for the whole scene, petals carried furthest.
        p.drift = _wind * (kind === "petals" ? _r(20, 45) : kind === "leaves" ? _r(5, 20) : _r(0, 6)) * u
        p.x0 = _r(-0.1, 1.1) * w
        p.y = anywhere ? _r(-0.1, 1) * h : -_r(0.05, 0.25) * h
        return p
    }
    property real _wind: 1

    function _reset() {
        _wind = Math.random() < 0.5 ? -1 : 1
        const ps = []
        for (let i = 0; i < count; i++)
            ps.push(_make(i, true))
        _ps = ps
        _place()
    }
    onCountChanged: Qt.callLater(_reset)
    onKindChanged: Qt.callLater(_reset)

    // One step of `dt` seconds for every one, then onto the items.
    function _step(dt) {
        const h = height
        for (let i = 0; i < _ps.length; i++) {
            const p = _ps[i]
            p.t += dt
            if (kind === "fireflies")
                continue
            p.age += dt
            p.y += p.v * dt
            if (p.rot !== undefined)
                p.rot += p.spin * dt
            if (p.y > h + p.size * 2)                         // out at the bottom: in again at the top
                _respawn(p)
        }
        _place()
    }

    // In again above the top, somewhere else across: its size, colour and
    // pace stay, as its item has them.
    function _respawn(p) {
        p.x0 = _r(-0.1, 1.1) * width
        p.y = -_r(0.05, 0.25) * height
        p.age = 0
    }

    function _place() {
        for (let i = 0; i < _ps.length; i++) {
            const it = drops.itemAt(i)
            if (!it)
                continue
            const p = _ps[i]
            if (kind === "fireflies") {
                const glow = Math.max(0, Math.sin(p.t * p.gw + p.gph))
                it.x = p.cx + p.ax * Math.sin(p.t * p.wx + p.phx) + p.ax * 0.4 * Math.sin(p.t * p.wx * 2.3 + p.phy) - p.size / 2
                it.y = p.cy + p.ay * Math.sin(p.t * p.wy + p.phy) - p.size / 2
                it.opacity = 0.08 + 0.92 * glow * glow
                it.scale = 0.6 + 0.4 * glow
                continue
            }
            const swing = Math.sin(p.t * p.w + p.ph)
            it.x = p.x0 + p.drift * p.age + p.sway * swing - p.size / 2
            it.y = p.y - p.size / 2
            it.opacity = p.alpha
            if (kind === "petals") {
                it.rotation = p.rot
                it.flip = Math.cos(p.t * p.fw + p.fph)         // turning over: edge-on at 0, its back below
            } else if (kind === "leaves") {
                it.rotation = p.base + p.tilt * swing           // rocks with its swing
                it.flip = Math.cos(p.t * p.fw + p.fph)
            }
        }
    }

    // ---- Clock: wall-clock slots of 1/maxFps s, as Backdrop's (which see).
    property real _last: 0
    readonly property bool _slotted: playing && maxFps > 0
    on_SlottedChanged: _arm(true)
    onMaxFpsChanged: _arm(false)
    function _arm(fresh) {
        if (fresh)
            _last = Date.now()
        if (!_slotted) {
            slots.stop()
            return
        }
        const slot = 1000 / maxFps
        slots.interval = Math.max(1, Math.ceil(slot - Date.now() % slot))
        slots.restart()
    }
    Timer {
        id: slots
        onTriggered: {
            const now = Date.now()
            weather._step(Math.max(0, Math.min((now - weather._last) / 1000, 0.25)))
            weather._last = now
            weather._arm(false)
        }
    }
    readonly property bool _windowShown: Window.window !== null
                                         && Window.visibility !== Window.Hidden
                                         && Window.visibility !== Window.Minimized

    Component.onCompleted: {
        _reset()
        _arm(true)
    }

    // ------------------------------------------------------------------
    // The items. Only the kind shown is built.

    property alias _drops: drops
    Repeater {
        id: drops
        model: weather.count
        delegate: Item {
            id: drop
            required property int index
            readonly property var _p: weather._ps[index] || ({ size: 8, tone: 0 })
            property real flip: 1
            width: _p.size
            height: weather.kind === "leaves" ? _p.size * 0.56 : weather.kind === "petals" ? _p.size * 0.82 : _p.size
            transform: Scale { origin.x: drop.width / 2; origin.y: drop.height / 2; yScale: drop.flip }
            Loader {
                anchors.fill: parent
                sourceComponent: weather.kind === "snow" ? flake
                               : weather.kind === "petals" ? petal
                               : weather.kind === "leaves" ? leaf : firefly
                readonly property color tone: weather.kind === "snow" ? weather.snow
                                            : weather.kind === "petals" ? weather.petals[drop._p.tone % 3]
                                            : weather.kind === "leaves" ? weather.leaves[drop._p.tone % 4]
                                            : weather.flies[drop._p.tone % 2]
            }
        }
    }

    // A flake: a soft round dot.
    Component {
        id: flake
        Rectangle {
            radius: width / 2
            color: parent ? parent.tone : weather.snow
            antialiasing: true
        }
    }

    // A glow with a bright heart.
    Component {
        id: firefly
        Shape {
            id: glowShape
            readonly property color tone: parent ? parent.tone : weather.flies[0]
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: glowShape.width / 2; centerY: glowShape.height / 2
                    centerRadius: glowShape.width / 2
                    focalX: centerX; focalY: centerY
                    GradientStop { position: 0.0; color: weather._mix(glowShape.tone, "#FFFFFF", 0.6) }
                    GradientStop { position: 0.14; color: glowShape.tone }
                    GradientStop { position: 0.4; color: Qt.rgba(glowShape.tone.r, glowShape.tone.g, glowShape.tone.b, 0.3) }
                    GradientStop { position: 1.0; color: Qt.rgba(glowShape.tone.r, glowShape.tone.g, glowShape.tone.b, 0) }
                }
                PathAngleArc {
                    centerX: glowShape.width / 2; centerY: glowShape.height / 2
                    radiusX: glowShape.width / 2; radiusY: glowShape.height / 2
                    startAngle: 0; sweepAngle: 360
                }
            }
        }
    }

    // A cherry petal: a rounded teardrop, its point where it met the flower,
    // a notch in its round end.
    Component {
        id: petal
        Shape {
            id: petalShape
            readonly property color tone: parent ? parent.tone : weather.petals[0]
            readonly property real w: width
            readonly property real h: height
            ShapePath {
                strokeWidth: -1
                fillGradient: LinearGradient {
                    x1: 0; y1: 0; x2: petalShape.w; y2: petalShape.h
                    GradientStop { position: 0.0; color: weather._mix(petalShape.tone, "#FFFFFF", 0.35) }
                    GradientStop { position: 0.7; color: petalShape.tone }
                }
                startX: 0.02 * petalShape.w; startY: 0.5 * petalShape.h
                PathCubic { x: 0.98 * petalShape.w; y: 0.38 * petalShape.h
                            control1X: 0.25 * petalShape.w; control1Y: -0.05 * petalShape.h
                            control2X: 0.85 * petalShape.w; control2Y: -0.05 * petalShape.h }
                PathLine { x: 0.84 * petalShape.w; y: 0.5 * petalShape.h }
                PathLine { x: 0.98 * petalShape.w; y: 0.62 * petalShape.h }
                PathCubic { x: 0.02 * petalShape.w; y: 0.5 * petalShape.h
                            control1X: 0.85 * petalShape.w; control1Y: 1.05 * petalShape.h
                            control2X: 0.25 * petalShape.w; control2Y: 1.05 * petalShape.h }
            }
        }
    }

    // A leaf: pointed at both ends, its midrib end to end.
    Component {
        id: leaf
        Shape {
            id: leafShape
            readonly property color tone: parent ? parent.tone : weather.leaves[0]
            readonly property real w: width
            readonly property real h: height
            ShapePath {
                strokeWidth: -1
                fillGradient: LinearGradient {
                    x1: 0; y1: 0; x2: leafShape.w * 0.4; y2: leafShape.h
                    GradientStop { position: 0.0; color: leafShape.tone }
                    GradientStop { position: 1.0; color: weather._mix(leafShape.tone, "#000000", 0.25) }
                }
                startX: 0.02 * leafShape.w; startY: 0.5 * leafShape.h
                PathQuad { x: 0.98 * leafShape.w; y: 0.5 * leafShape.h; controlX: 0.45 * leafShape.w; controlY: -0.35 * leafShape.h }
                PathQuad { x: 0.02 * leafShape.w; y: 0.5 * leafShape.h; controlX: 0.55 * leafShape.w; controlY: 1.35 * leafShape.h }
            }
            ShapePath {
                strokeColor: weather._mix(leafShape.tone, "#FFFFFF", 0.45)
                strokeWidth: Math.max(1, leafShape.h * 0.07)
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                startX: 0.06 * leafShape.w; startY: 0.5 * leafShape.h
                PathLine { x: 0.94 * leafShape.w; y: 0.5 * leafShape.h }
            }
        }
    }
}
