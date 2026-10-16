pragma Singleton
import QtQuick
import McFly

// The glass the controls are made of ("Lens": shaders/lens.frag through
// components/Lens.qml). What every lens shares lives here: the aura it
// bends, the inks that read on it, and how far into the night look it is.
//
// The aura is the glow's four colours (Theme.glowBlue, glowCoral, glowAmber,
// glowCream) as colour fields fixed to the window: blue to the top left,
// coral to the right, amber along the bottom, a soft highlight right of
// centre. It is GradientTile's palette (luminous pastels by day, deep tones
// at night) held still. The rail shows it faintly (a `wash`); an active
// control gathers more of it, so the nav pill shows a different part of it
// wherever it is.
//
// `darkness` follows Theme.dark, eased over the palette's own fade (a Dark
// mode tap is quick, a mood change slow), so the inks and the glass turn
// with the rest of the screen instead of switching at once. `mix(day,
// night)` reads a value along it.
Item {
    id: glass
    visible: false

    property real darkness: 0
    function mix(day, night) { return day + (night - day) * darkness }

    // Ink on an active lens: the accent deepened by day, a pale accent at
    // night. White on the plain accent misses 4.5:1 in every mood.
    readonly property color ink: _accentAt(mix(0.44, 0.87), mix(1.0, 0.75))
    // A primary button's body: the accent, deep enough for white ink.
    readonly property color primary: _accentAt(mix(0.44, 0.50), 1.0)
    // How much aura a surface shows (the rail), and an active lens gathers.
    readonly property real wash: mix(0.13, 0.20)
    readonly property real gather: mix(0.38, 0.50)

    // ---- The aura, for the shader: the fields in OKLab with their chroma,
    // and where they sit as shares of the window.
    readonly property vector4d aura0: _fields[0]
    readonly property vector4d aura1: _fields[1]
    readonly property vector4d aura2: _fields[2]
    readonly property vector4d aura3: _fields[3]
    readonly property vector2d auraAt0: Qt.vector2d(0.10, 0.10)
    readonly property vector2d auraAt1: Qt.vector2d(0.90, 0.30)
    readonly property vector2d auraAt2: Qt.vector2d(0.45, 1.00)
    readonly property vector2d auraAt3: Qt.vector2d(0.62, 0.62)
    // The glow along a caustic: blue, coral, amber.
    readonly property vector4d glow0: _lab(Theme.glowBlue)
    readonly property vector4d glow1: _lab(Theme.glowCoral)
    readonly property vector4d glow2: _lab(Theme.glowAmber)

    // ------------------------------------------------------------------
    // Internals

    function _accentAt(lightness, chroma) {
        const v = Theme.oklab(Theme.accent)
        return Theme.fromOklab([lightness, v[1] * chroma, v[2] * chroma, 1])
    }
    function _lab(c) { const v = Theme.oklab(c); return Qt.vector4d(v[0], v[1], v[2], 0) }
    function _clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
    function _mixc(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
    }
    // GradientTile's pastel saturation, greys eased back to grey.
    function _sat(s) {
        const k = _clamp(s / 0.24, 0, 1)
        return s + (_clamp(s, 0.38, 0.78) - s) * k * k * (3 - 2 * k)
    }
    readonly property var _src: [Theme.glowBlue, Theme.glowCoral, Theme.glowAmber, Theme.glowCream].map(c => {
        const k = Qt.lighter(c, 1.0)
        return k.hslHue < 0 ? { h: 0, s: 0 } : { h: k.hslHue, s: k.hslSaturation }
    })
    readonly property var _fields: {
        const day = [0.79, 0.83, 0.76, 0.94], night = [0.19, 0.22, 0.15, 0.27]
        const daySat = [1, 1, 1, 0.8], nightSat = [0.55, 0.5, 0.5, 0.45]
        return _src.map((c, i) => {
            const v = Theme.oklab(_mixc(Qt.hsla(c.h, _sat(c.s) * daySat[i], day[i], 1),
                                        Qt.hsla(c.h, _sat(c.s) * nightSat[i], night[i], 1), darkness))
            return Qt.vector4d(v[0], v[1], v[2], Math.hypot(v[1], v[2]))
        })
    }

    // `darkness` eases to Theme.dark over the fade Theme is running (settled
    // once Theme has seen the change too, hence the callLater).
    readonly property bool _dark: Theme.dark
    on_DarkChanged: Qt.callLater(glass._fade)
    function _fade() {
        fade.stop()
        fade.duration = Theme.paletteFade
        fade.to = Theme.dark ? 1 : 0
        fade.start()
    }
    NumberAnimation { id: fade; target: glass; property: "darkness"; easing.type: Easing.InOutSine }
    Component.onCompleted: darkness = Theme.dark ? 1 : 0
}
