import QtQuick
import McFly
import McFly.Core

// A sky for the screen savers and the assistant: one of five moving
// backdrops in the glow colours, each a fragment shader of its own
// (shaders/<style>.frag), laid on the canvas by an OKLab mix so it is a pastel
// wash on the warm canvas by day and a glow over the near-black one at night.
// Decorative; what goes on top reads in `ink` and `inkMuted`.
//
//   Backdrop {
//       anchors.fill: parent
//       style: Device.backdrop      // arc | ribbons | dawn | silk | pillars
//       darkness: ambient.dusk      // or leave it to follow Theme.dark
//       whileIdle: true             // a screen saver's own backdrop
//       maxFps: Theme.saverFps
//   }
//
// Arc: an aurora band curving across the sky, bright along its lower edge,
// rays running up through it. Ribbons: three thin curtains edge-on, folding.
// Dawn: a horizon gradient, a low sun glow, haze. Silk: two sheets of satin
// folding over each other. Pillars: columns of light standing up from the
// bottom edge. (Mesh, the savers' other choice, is GradientTile.)
//
// Cost is simplex noise lookups per pixel, from none (silk) to nine
// (ribbons), so each runs at a fraction of the item's size that suits it (a
// soft picture loses nothing scaled up) and moves at `maxFps`. As with
// GradientTile, the clock only ticks while it can be seen and Settings →
// Animated tiles is on; it resumes where it stopped. The colours, the canvas
// and the strength are read on the clock's ticks, so a palette fade (Theme's,
// in OKLab) moves the picture at maxFps and the frames between redraw
// nothing; with the clock stopped they change at once. Where shaders don't
// run (software rendering) it draws a plain two-stop gradient.
Item {
    id: sky

    // ---- Look
    property string style: "arc"
    property var colors: [Theme.glowBlue, Theme.glowCoral, Theme.glowAmber, Theme.glowCream]   // 4 stops
    // Night look: a deep canvas, the light a glow rather than a wash.
    property bool dark: Theme.dark
    property int moodFade: Theme.moodFade   // how long `dark` takes to come in (a Dark mode tap: Theme.themeFade)
    // How far into the night look, 0..1. It follows `dark`; bind it instead
    // to bring the night in on a clock of your own (the ambient saver's dusk).
    property real darkness: _dkEase
    property color dayCanvas: Theme.palettes["day"].background
    property color nightCanvas: Theme.darkMode ? Theme.darkPalette.background : Theme.palettes["night"].background
    property real brightness: 1.0           // scales the style's own strength

    // ---- Motion
    property bool animated: Device.animatedTiles   // off: frozen where it is
    property bool active: true              // false while its page isn't showing
    property bool whileIdle: false          // a screen saver's backdrop keeps going while idle
    property real speed: 1.0
    property int maxFps: Theme.motionFps    // motion updates per second (0 = every frame)
    property real seed: 0                   // a different sky
    property real resolution: _look.resolution   // fraction of the item's size the shader runs at

    // ---- Read-only helpers for content on top
    readonly property color canvas: _mixOklab(dayCanvas, nightCanvas, _dk)
    readonly property color ink: _mixc("#1D1B24", Qt.rgba(1, 1, 1, 0.92), _inkDk)        // titles, numbers
    readonly property color inkMuted: _mixc("#4A4555", Qt.rgba(1, 1, 1, 0.62), _inkDk)   // secondary text
    // How much of the light lands on the canvas: each style's own, by day
    // and at night, times `brightness`.
    readonly property real strength: Math.max(0, Math.min(1, (_look.strength[0] + (_look.strength[1] - _look.strength[0]) * _dk) * brightness))
    // The shader drawn: the style, or the arc for a name this build doesn't know.
    readonly property string shader: _looks[style] !== undefined ? style : "arc"

    readonly property bool fallback: GraphicsInfo.api === GraphicsInfo.Software
                                     || fx.status === ScaledShader.Error
    readonly property bool playing: animated && active && visible && (whileIdle ? !Device.screenOff : !Device.idle)
                                    && width > 0 && height > 0 && !fallback && _windowShown

    // ------------------------------------------------------------------
    // Internals

    readonly property bool _windowShown: Window.window !== null
                                         && Window.visibility !== Window.Hidden
                                         && Window.visibility !== Window.Minimized

    // Each style's strength [day, night] and the resolution it runs at.
    readonly property var _looks: ({
        "arc":     { strength: [0.70, 0.95], resolution: 0.5 },
        "ribbons": { strength: [0.90, 1.00], resolution: 0.4 },
        "dawn":    { strength: [0.50, 0.90], resolution: 0.5 },
        "silk":    { strength: [0.50, 0.85], resolution: 0.5 },
        "pillars": { strength: [0.85, 0.95], resolution: 0.5 }
    })
    readonly property var _look: _looks[shader]

    readonly property real _dk: Math.max(0, Math.min(1, darkness))
    // The ink turns from dark to light quickly in the middle of the fade,
    // where the canvas is mid-tone, so text never sits grey on grey for long
    // (the ambient saver's dusk takes a minute).
    readonly property real _inkDk: {
        const x = Math.max(0, Math.min(1, (_dk - 0.44) / 0.12))
        return x * x * (3 - 2 * x)
    }
    // `dark` eases in over moodFade, or quickly when the Dark mode setting
    // flipped it (Theme.paletteFade, where Theme keeps one); which it was is
    // only settled once Theme has seen the change too, hence the callLater
    // (as in GradientTile).
    property real _dkEase: 0
    onDarkChanged: Qt.callLater(sky._fadeDark)
    function _fadeDark() {
        dkFade.stop()
        dkFade.duration = Math.min(sky.moodFade, Theme.paletteFade || sky.moodFade)
        dkFade.to = sky.dark ? 1 : 0
        dkFade.start()
    }
    NumberAnimation { id: dkFade; target: sky; property: "_dkEase"; easing.type: Easing.InOutSine }

    // ---- Colour in OKLab: [L, a, b]. A blend in it keeps lightness even and
    // takes hues the short way, where RGB greys out (the arithmetic AuroraGlow
    // and GradientTile use).
    function _oklab(c) {
        const k = Qt.lighter(c, 1.0)   // accepts colour values and strings
        const lin = x => x <= 0.04045 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4)
        const r = lin(k.r), g = lin(k.g), b = lin(k.b)
        const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s]
    }
    function _fromOklab(v) {
        const l = v[0] + 0.3963377774 * v[1] + 0.2158037573 * v[2]
        const m = v[0] - 0.1055613458 * v[1] - 0.0638541728 * v[2]
        const s = v[0] - 0.0894841775 * v[1] - 1.2914855480 * v[2]
        const L = l * l * l, M = m * m * m, S = s * s * s
        const enc = x => {
            x = Math.max(0, Math.min(1, x))
            return x <= 0.0031308 ? 12.92 * x : 1.055 * Math.pow(x, 1 / 2.4) - 0.055
        }
        return Qt.rgba(enc( 4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S),
                       enc(-1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S),
                       enc(-0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S), 1)
    }
    function _mixOklab(a, b, t) {
        const x = _oklab(a), y = _oklab(b)
        return _fromOklab(x.map((v, i) => v + (y[i] - v) * t))
    }

    function _mixc(a, b, t) {
        const x = Qt.lighter(a, 1.0), y = Qt.lighter(b, 1.0)   // accepts colours and strings
        return Qt.rgba(x.r + (y.r - x.r) * t, x.g + (y.g - x.g) * t, x.b + (y.b - x.b) * t, x.a + (y.a - x.a) * t)
    }

    // The stops in OKLCh (lightness, chroma, hue in radians), each hue
    // unwrapped toward the one before, so the shader's blend between
    // neighbours takes the short way round; a grey stop takes its
    // neighbour's hue (AuroraGlow does the same).
    function _oklch(c) {
        const v = _oklab(c)
        return [v[0], Math.hypot(v[1], v[2]), Math.atan2(v[2], v[1])]
    }
    readonly property var _stops: {
        const src = (colors || []).slice(0, 4)
        while (src.length < 4)
            src.push(src.length ? src[src.length - 1] : Theme.accent)
        const lch = src.map(c => _oklch(c))
        const known = lch.findIndex(c => c[1] > 0.02)
        let previous = known === -1 ? 0 : lch[known][2]
        return lch.map(c => {
            let hue = c[1] > 0.02 ? c[2] : previous
            while (hue - previous > Math.PI) hue -= 2 * Math.PI
            while (hue - previous < -Math.PI) hue += 2 * Math.PI
            previous = hue
            return [c[0], c[1], hue]
        })
    }

    // What the shader is fed: read on the clock's ticks while it runs, at
    // once while it is stopped.
    property var _shownStops: [[0, 0, 0], [0, 0, 0], [0, 0, 0], [0, 0, 0]]
    property var _shownCanvas: [0, 0, 0]
    property real _shownStrength: 0
    function _sample() {
        _shownStops = _stops
        _shownCanvas = _oklab(canvas)
        _shownStrength = strength
    }
    on_StopsChanged: if (!playing) _sample()
    onCanvasChanged: if (!playing) _sample()
    onStrengthChanged: if (!playing) _sample()
    onPlayingChanged: if (!playing) _sample()
    function _stop(i) {
        const c = _shownStops[i]
        return Qt.vector4d(c[0], c[1], c[2], 0)
    }

    // Clock: capped (maxFps > 0), a Timer on wall-clock slots of 1/maxFps s,
    // the same slots GradientTile, AuroraGlow and SpectrumGlow use, so a
    // saver's layers change on the same frames and the render loop sleeps in
    // between (a FrameAnimation skipping frames kept it drawing at the
    // display's rate). A step is never negative and at most 0.25 s, so a
    // jump of the wall clock can't run it backwards. Uncapped: every frame.
    // It starts from the wall clock, within the hour: each showing opens on a
    // different sky, and the time stays small enough for the shader's 32-bit
    // floats to step evenly.
    property real _time: 0
    function _advance(dt) {
        _time += Math.max(0, Math.min(dt, 0.25)) * speed
        _sample()
    }
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
            sky._advance((now - sky._last) / 1000)
            sky._last = now
            sky._arm(false)
        }
    }
    FrameAnimation {
        id: clock
        running: sky.playing && sky.maxFps <= 0
        onTriggered: sky._advance(clock.frameTime)
    }

    Component.onCompleted: {
        _dkEase = dark ? 1 : 0
        _time = (Date.now() / 1000 % 3600) * speed + seed * 37
        _sample()
        _arm(true)
    }

    ScaledShader {
        id: fx
        anchors.fill: parent
        visible: !sky.fallback
        // Rendered smaller and scaled up: the skies have no hard edges. In
        // pixels, as a layer's textureSize was; at 1, the item's own.
        fixedColorBufferWidth: sky.resolution < 1 ? Math.max(1, Math.ceil(width * sky.resolution)) : 0
        fixedColorBufferHeight: sky.resolution < 1 ? Math.max(1, Math.ceil(height * sky.resolution)) : 0
        // Uniforms (names match shaders/<style>.frag).
        readonly property size size: Qt.size(width, height)
        readonly property real time: sky._time
        readonly property real strength: sky._shownStrength
        readonly property real seed: sky.seed
        // The opacity the picture gets after the shader (the item's, applied
        // as the picture is drawn): the dither is scaled to it so it stays one
        // step on screen. In steps of 0.05, so a fade re-shades a few times
        // rather than every frame.
        readonly property real dim: Math.max(0.1, Math.round(sky.opacity * 20) / 20)
        readonly property vector4d canvas: Qt.vector4d(sky._shownCanvas[0], sky._shownCanvas[1], sky._shownCanvas[2], 0)
        readonly property vector4d s0: sky._stop(0)
        readonly property vector4d s1: sky._stop(1)
        readonly property vector4d s2: sky._stop(2)
        readonly property vector4d s3: sky._stop(3)
        fragmentShader: "qrc:/McFly/shaders/" + sky.shader + ".frag.qsb"
    }

    // Software rendering: the canvas with a little of the first two stops.
    Rectangle {
        anchors.fill: parent
        visible: sky.fallback
        gradient: Gradient {
            GradientStop { position: 0; color: sky._mixOklab(sky.canvas, sky.colors[0] || Theme.accent, 0.5 * sky.strength) }
            GradientStop { position: 1; color: sky._mixOklab(sky.canvas, sky.colors[1] || Theme.accent, 0.3 * sky.strength) }
        }
    }
}
