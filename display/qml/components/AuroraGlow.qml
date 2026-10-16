import QtQuick
import McFly
import McFly.Core

// An aurora: a curtain of light in the glow colours hangs from the top edge,
// its hem rolling slowly, the colour running left to right. React Bits'
// Aurora (shaders/aurora.frag has its licence: MIT + Commons Clause), the same
// one the console draws on its night-time ambient view (admin/components/
// GlowAurora.tsx). Decorative; lay it over a backdrop, under the content.
//
//   AuroraGlow {
//       anchors.fill: parent
//       whileIdle: true          // a screen saver's own backdrop
//       opacity: 0.45            // the strength is the item's opacity
//   }
//
// Cost: four noise lookups per pixel and layer, so it runs at `resolution`
// of the item's size (a soft curtain loses nothing scaled up) and moves at
// `maxFps`. Like GradientTile, the clock only ticks while it can be seen and
// Settings → Animated tiles is on; it resumes where it stopped. Where
// shaders don't run (software rendering) it draws nothing.
Item {
    id: aurora

    // ---- Look
    property var colors: [Theme.glowBlue, Theme.glowCoral, Theme.glowAmber, Theme.glowBlue]   // 2-5, left to right
    property bool lightMode: !Theme.dark   // a tint on a light canvas; false: light over a dark one
    property real hem: 0.45                // where the hem rests, 0 (top) .. 1 (bottom)
    property real amplitude: 1.0           // how tall the waves along the hem are
    property real blend: 0.5               // 0..1, how softly the hem fades out
    property real waveScale: 1.0           // horizontal frequency of the waves
    property real glow: 0.6                // how far the light spills past the hem
    property real brightness: 1.0          // 0..2
    property int layers: 1                 // 1-3 curtains, one behind the other
    property bool fromBottom: false        // rise from the bottom edge instead

    // ---- Motion
    property bool animated: Device.animatedTiles   // off: frozen where it is
    property bool active: true             // false while its page isn't showing
    property bool whileIdle: false         // a screen saver's backdrop keeps going while idle
    property real speed: 1.0
    property int maxFps: 15                // motion updates per second (0 = every frame)
    property bool intro: true              // lower the curtain into place when it first runs
    property real resolution: 0.5          // fraction of the item's size the shader runs at

    readonly property bool fallback: GraphicsInfo.api === GraphicsInfo.Software
                                     || fx.status === ShaderEffect.Error
    readonly property bool playing: animated && active && visible && (whileIdle ? !Device.screenOff : !Device.idle)
                                    && width > 0 && height > 0 && !fallback && _windowShown

    // ------------------------------------------------------------------
    // Internals

    readonly property bool _windowShown: Window.window !== null
                                         && Window.visibility !== Window.Hidden
                                         && Window.visibility !== Window.Minimized

    // The stops in OKLCh (lightness, chroma, hue), with each hue unwrapped
    // toward the one before so the blend takes the short way round.
    function _oklch(c) {
        const k = Qt.lighter(c, 1.0)   // accepts colour values and strings
        const lin = x => x <= 0.04045 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4)
        const r = lin(k.r), g = lin(k.g), b = lin(k.b)
        const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        const L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s
        const A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s
        const B = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
        return [L, Math.hypot(A, B), Math.atan2(B, A)]
    }
    readonly property var _stops: {
        const src = (colors && colors.length >= 2 ? colors : [Theme.glowBlue, Theme.glowCoral]).slice(0, 5)
        const lch = src.map(c => _oklch(c))
        const known = lch.findIndex(c => c[1] > 0.02)
        let previous = known === -1 ? 0 : lch[known][2]
        return lch.map(c => {
            let hue = c[1] > 0.02 ? c[2] : previous
            while (hue - previous > Math.PI) hue -= 2 * Math.PI
            while (hue - previous < -Math.PI) hue += 2 * Math.PI
            previous = hue
            return Qt.vector4d(c[0], c[1], hue, 0)
        })
    }
    function _stop(i) { return _stops[Math.min(i, _stops.length - 1)] }

    // Clock and intro. Real elapsed time, quantised to wall-clock slots of
    // 1/maxFps s (the same slots GradientTile uses, so a saver's backdrop and
    // its aurora change on the same frames and the ones between redraw nothing).
    property real _time: 0
    property real _reveal: intro ? 0 : 1
    property real _last: 0
    property real _slot: -1
    readonly property real _shownReveal: animated ? 1 - Math.pow(1 - _reveal, 3) : 1
    FrameAnimation {
        running: aurora.playing
        onRunningChanged: if (running) aurora._last = Date.now()
        onTriggered: {
            const now = Date.now()
            if (aurora.maxFps > 0) {
                const slot = Math.floor(now * aurora.maxFps / 1000)
                if (slot === aurora._slot) return
                aurora._slot = slot
            }
            const dt = Math.min((now - aurora._last) / 1000, 0.25)
            aurora._last = now
            aurora._time += dt * aurora.speed
            if (aurora._reveal < 1) aurora._reveal = Math.min(1, aurora._reveal + dt / 2.4)
        }
    }

    ShaderEffect {
        id: fx
        anchors.fill: parent
        visible: !aurora.fallback
        blending: true
        // Rendered smaller and scaled up: the curtain has no hard edges.
        layer.enabled: aurora.resolution < 1
        layer.textureSize: Qt.size(Math.max(1, Math.ceil(width * aurora.resolution)),
                                   Math.max(1, Math.ceil(height * aurora.resolution)))
        layer.smooth: true
        // Uniforms (names match shaders/aurora.frag).
        readonly property size size: Qt.size(width, height)
        readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
        readonly property real time: aurora._time
        readonly property real reveal: aurora._shownReveal
        readonly property real amplitude: aurora.amplitude
        readonly property real blend: aurora.blend
        readonly property real hem: aurora.hem
        readonly property real waveScale: aurora.waveScale
        readonly property real glow: aurora.glow
        readonly property real brightness: aurora.brightness
        readonly property real layers: Math.max(1, Math.min(3, aurora.layers))
        readonly property real flip: aurora.fromBottom ? 1 : 0
        readonly property real lightMode: aurora.lightMode ? 1 : 0
        readonly property real stopCount: aurora._stops.length
        readonly property vector4d s0: aurora._stop(0)
        readonly property vector4d s1: aurora._stop(1)
        readonly property vector4d s2: aurora._stop(2)
        readonly property vector4d s3: aurora._stop(3)
        readonly property vector4d s4: aurora._stop(4)
        fragmentShader: "qrc:/McFly/shaders/aurora.frag.qsb"
    }
}
