import QtQuick
import McFly

// The glass the controls are made of: a rounded rect of `fill`, lit like
// glass (a rim from the top left, a sheen, a soft shadow), drawn by
// shaders/lens.frag in one pass. Put it behind a control's content, sized
// to the control; the shadow reaches past it on its own.
//
//   Lens { anchors.fill: parent; kind: "active" }               // the nav pill
//   Lens { anchors.fill: parent; fill: btn.fill }                // a resting button
//   Lens { anchors.fill: parent; kind: "primary" }               // Read aloud
//
// `kind` picks the treatment; any of the numbers below can still be set.
//   active   the chosen thing (nav pill, segment thumb, chosen chip, Ask):
//            clear glass over the surface, gathering the aura (Glass.qml)
//            with a caustic of the glow along its lower edge. Ink: Glass.ink.
//   rest     a button at rest: its fill, a rim, a sheen, a light shadow.
//   primary  the main action: Glass.primary under white ink, a caustic, a
//            shadow in its own colour.
//   wash     a whole surface showing the aura faintly (the rail). Flat: no
//            rim, sheen or shadow. Still, so it is worth caching as a layer.
//
// The aura is fixed to the window, so the lens maps where it is: when it,
// or its parent, moves or resizes. A move further up (a list scrolling)
// leaves it reading the aura a little off, which a field this soft hides.
// No shaders (software rendering): a plain rounded rect of `fill`, or of
// Theme.accentSoft for an active lens.
Item {
    id: lens

    property string kind: "rest"
    property color fill: kind === "primary" ? Glass.primary
                       : kind === "wash" ? "transparent" : Theme.surface
    property real radius: Math.min(width, height) / 2

    readonly property bool _active: kind === "active"
    readonly property bool _primary: kind === "primary"
    readonly property bool _wash: kind === "wash"

    property real gather: _wash ? Glass.wash : _active ? Glass.gather : _primary ? Glass.mix(0.10, 0.16) : 0
    property real saturation: _active ? Glass.mix(1.5, 1.6) : _primary ? 1.2 : 1.0
    property real magnify: _wash ? 1.0 : 0.86
    property real bend: _wash ? 0 : 9
    property real dispersion: _wash ? 0 : 2.2
    property real lift: _active ? Glass.mix(0.14, 0.06) : 0
    property real caustic: _active ? Glass.mix(0.32, 0.42) : _primary ? Glass.mix(0.18, 0.26) : 0
    property real sheen: _wash ? 0 : _primary ? Glass.mix(0.20, 0.08) : Glass.mix(0.20, 0.06)
    property real rim: _wash ? 0 : _active ? Glass.mix(0.85, 0.50) : _primary ? Glass.mix(0.60, 0.42) : Glass.mix(0.75, 0.42)
    property real shadow: _wash ? 0 : _active ? Glass.mix(0.10, 0.32) : _primary ? Glass.mix(0.26, 0.40) : Glass.mix(0.07, 0.25)
    property real shadowY: _primary ? 6 : _active ? 3 : 2
    property real shadowBlur: _primary ? 10 : _active ? 6 : 5
    property color shadowColor: _primary ? fill : "black"

    readonly property bool fallback: GraphicsInfo.api === GraphicsInfo.Software
                                     || fx.status === ShaderEffect.Error

    // ---- Where it is in the window, for the aura.
    property point _origin: Qt.point(0, 0)
    readonly property var _window: Window.window
    function _place() {
        if (gather <= 0 || !_window)
            return
        const at = mapToItem(null, 0, 0)
        if (at.x !== _origin.x || at.y !== _origin.y)
            _origin = at
    }
    onXChanged: _place()
    onYChanged: _place()
    onWidthChanged: _place()
    onHeightChanged: _place()
    onGatherChanged: _place()
    on_WindowChanged: _place()
    Connections {
        target: lens.parent
        ignoreUnknownSignals: true
        function onXChanged() { lens._place() }
        function onYChanged() { lens._place() }
    }
    Component.onCompleted: _place()

    ShaderEffect {
        id: fx
        readonly property real pad: lens.shadow > 0 ? Math.ceil(lens.shadowY + 3 * lens.shadowBlur) : 1
        x: -pad
        y: -pad
        width: lens.width + 2 * pad
        height: lens.height + 2 * pad
        visible: !lens.fallback && lens.width > 0 && lens.height > 0
        // Cached: the glass is drawn again only when what it shows changes
        // (it moves, the palette fades), not on every frame something else
        // moves (Home's ticker runs at the display's rate). That is rare, so
        // the one extra frame Qt draws after a layer changes costs nothing
        // here. A texel a pixel.
        // Not a wash: the rail caches that one whole, at a quarter size.
        layer.enabled: !lens._wash
        // Sampled smoothly. At QT_SCALE_FACTOR=1.5 (the 10.1" panel) a control
        // often lands on half a pixel, and nearest sampling there doubled some
        // of the glass's columns on the Pi's GPU: Ask and the nav pill looked
        // pixelated. On whole pixels smooth sampling is exact.
        layer.smooth: true
        layer.textureSize: Qt.size(Math.max(1, Math.ceil(width * dpr)), Math.max(1, Math.ceil(height * dpr)))
        // Uniforms (names match shaders/lens.frag).
        readonly property size size: Qt.size(width, height)
        readonly property real radius: lens.radius
        readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
        readonly property color fill: lens.fill
        readonly property real gather: lens.gather
        readonly property real saturation: lens.saturation
        readonly property real magnify: lens.magnify
        readonly property real bend: lens.bend
        readonly property real dispersion: lens.dispersion
        readonly property real lift: lens.lift
        readonly property real caustic: lens.caustic
        readonly property real sheen: lens.sheen
        readonly property real rim: lens.rim
        readonly property vector4d shadow: Qt.vector4d(lens.shadowY, lens.shadowBlur, lens.shadow, 0)
        readonly property color shadowColor: lens.shadowColor
        readonly property point origin: lens._origin
        readonly property size window: lens._window ? Qt.size(lens._window.width, lens._window.height) : Qt.size(1, 1)
        readonly property vector4d aura0: Glass.aura0
        readonly property vector4d aura1: Glass.aura1
        readonly property vector4d aura2: Glass.aura2
        readonly property vector4d aura3: Glass.aura3
        readonly property vector2d auraAt0: Glass.auraAt0
        readonly property vector2d auraAt1: Glass.auraAt1
        readonly property vector2d auraAt2: Glass.auraAt2
        readonly property vector2d auraAt3: Glass.auraAt3
        readonly property vector4d glow0: Glass.glow0
        readonly property vector4d glow1: Glass.glow1
        readonly property vector4d glow2: Glass.glow2
        readonly property real dark: Glass.darkness
        fragmentShader: "qrc:/McFly/shaders/lens.frag.qsb"
    }

    // No shaders: the fill, except that an active lens (clear glass over the
    // surface it sits on) takes the accent's soft tint, under the same ink.
    Rectangle {
        anchors.fill: parent
        visible: lens.fallback
        radius: lens.radius
        color: lens._active ? Theme.accentSoft : lens.fill
    }
}
