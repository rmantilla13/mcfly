import QtQuick
import McFly
import McFly.Core

// An aurora: a curtain of light in the glow colours hangs from the top edge,
// its hem folding slowly, faint rays running down it, the colour running
// left to right. React Bits' Aurora (shaders/aurora.frag has its licence:
// MIT + Commons Clause), the same one the console draws on its night-time
// ambient view (admin/components/GlowAurora.tsx). Decorative; lay it over a
// backdrop, under the content.
//
//   AuroraGlow {
//       anchors.fill: parent
//       whileIdle: true          // a screen saver's own backdrop
//       opacity: 0.45            // the strength is the item's opacity
//   }
//
// Cost: five noise lookups per pixel and layer (four with `rays: 0`), so it
// runs at `resolution` of the item's size (a soft curtain loses nothing
// scaled up) and moves at `maxFps`. Like GradientTile, the clock only ticks
// while it can be seen and Settings → Animated tiles is on; it resumes where
// it stopped. A change of colours glides over 1.5 s, light mode over 0.6 s
// and the first showing fades in over 1.2 s, all on the clock's ticks; while
// Theme fades its palette the curtain follows the fade instead. With the
// clock stopped, colours and light mode simply change. Where shaders don't
// run (software rendering) it draws nothing.
Item {
    id: aurora

    // ---- Look
    property var colors: [Theme.glowBlue, Theme.glowCoral, Theme.glowAmber, Theme.glowBlue]   // 2-5, left to right
    property bool lightMode: !Theme.dark   // ink on a light canvas; false: light over a dark one
    property real hem: 0.45                // where the hem rests, 0 (top) .. 1 (bottom)
    property real amplitude: 1.0           // how tall the waves along the hem are
    property real blend: 0.5               // 0..1, how softly the hem fades out
    property real waveScale: 1.0           // horizontal frequency of the waves
    property real glow: 0.6                // how far the light spills past the hem
    property real brightness: 1.0          // 0..2
    property int layers: 1                 // 1-3 curtains, one behind the other
    property bool fromBottom: false        // rise from the bottom edge instead
    property real rays: 0.6                // 0..1, faint rays down the curtain; 0 also skips their noise

    // ---- Motion
    property bool animated: Device.animatedTiles   // off: frozen where it is
    property bool active: true             // false while its page isn't showing
    property bool whileIdle: false         // a screen saver's backdrop keeps going while idle
    property real speed: 1.0
    property int maxFps: Theme.motionFps   // motion updates per second (0 = every frame)
    property bool intro: false             // lower the curtain into place when it first runs (otherwise it fades in)
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

    // A colour in OKLCh (lightness, chroma, hue in radians).
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
    // Each hue unwrapped toward the one before, so the blend between
    // neighbouring stops takes the short way round.
    function _unwrap(lch) {
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
    readonly property var _stops: {
        const src = (colors && colors.length >= 2 ? colors : [Theme.glowBlue, Theme.glowCoral]).slice(0, 5)
        return _unwrap(src.map(c => _oklch(c)))
    }

    // A new palette glides in from the one on screen: stop by stop in OKLCh,
    // lightness and chroma straight across, the hue the short way round (a
    // grey stop takes its partner's hue). The console's Aurora.tsx does the same.
    function _blend(from, to, t) {
        return _unwrap(to.map((b, i) => {
            const a = from[i] !== undefined ? from[i] : b
            const ha = a[1] > 0.02 ? a[2] : b[2]
            const hb = b[1] > 0.02 ? b[2] : ha
            const turn = hb - ha - 2 * Math.PI * Math.round((hb - ha) / (2 * Math.PI))
            return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, ha + turn * t]
        }))
    }
    function _same(a, b) {
        return a.length === b.length
               && a.every((c, i) => Math.abs(c[0] - b[i][0]) < 1e-4 && Math.abs(c[1] - b[i][1]) < 1e-4
                                    && Math.abs(c[2] - b[i][2]) < 1e-4)
    }
    function _ease(t) { return 0.5 - 0.5 * Math.cos(Math.PI * t) }   // InOutSine
    // What's on screen follows from these three, which only the clock's ticks
    // (_retarget) and a stopped clock (_take) set. _shown never reads _stops,
    // so it can't loop back into the code that sets it.
    property var _from: []
    property var _to: []
    property real _glide: 1                // 0..1 through the glide, linear in time
    readonly property var _shown: _glide < 1 ? _blend(_from, _to, _ease(_glide)) : _to
    // The palette as it is: the first one, and any while the clock is stopped.
    function _take() {
        const next = _stops
        if (_glide >= 1 && _same(next, _to))
            return
        _glide = 1
        _from = next
        _to = next
    }
    on_StopsChanged: if (!playing) _take()
    // On a tick a new palette glides in, unless the stops are already easing
    // on their own (Theme fading its tokens, or a change on every tick): then
    // it follows them, since a glide of its own would start over on each tick
    // and trail the whole fade. A glide under way just heads for them.
    property bool _moving: false           // the stops changed on the last tick
    function _retarget(dt) {
        const next = _stops
        const changed = !_same(next, _to)
        const follow = Theme.fading || _moving
        _moving = changed
        if (changed) {
            if (next.length !== _to.length) {
                _take()
            } else if (follow) {
                if (_glide >= 1)
                    _from = next
                _to = next
            } else {
                _from = _shown
                _to = next
                _glide = 0
            }
        }
        if (_glide < 1)
            _glide = Math.min(1, _glide + dt / 1.5)
    }
    function _stop(i) {
        const c = _shown.length ? _shown[Math.min(i, _shown.length - 1)] : [0, 0, 0]
        return Qt.vector4d(c[0], c[1], c[2], 0)
    }

    // Light mode eases between the two looks rather than flipping, over 0.6 s
    // of ticks; with the clock stopped it just changes.
    property real _light: 0
    property real _lightFrom: 0
    property real _lightProgress: 1
    onLightModeChanged: {
        _lightFrom = _light
        _lightProgress = 0
        if (!playing)
            _settle()
    }

    // The hue's slow sway, per layer: two octaves of smooth 1D gradient noise
    // on the layer's own clock. The same for every pixel, so it's worked out
    // here once a tick, not in the shader. Aurora.tsx has the same function.
    function _lattice(i) {
        const s = Math.sin(i * 127.1 + 311.7) * 43758.5453
        return (s - Math.floor(s)) * 2 - 1
    }
    function _noise1(x) {
        const i = Math.floor(x)
        const f = x - i
        const s = f * f * f * (f * (f * 6 - 15) + 10)
        return 2 * (_lattice(i) * f * (1 - s) + _lattice(i + 1) * (f - 1) * s)
    }
    function _hueDrift(time, layer) {
        const pace = time * (1 - layer * 0.18)
        return 0.07 * (0.7 * _noise1(pace * 0.03 + layer * 3.1) + 0.3 * _noise1(pace * 0.071 + 7.7 + layer * 1.3))
    }

    // Clock, intro and fade-in. Capped (maxFps > 0), a Timer on wall-clock
    // slots of 1/maxFps s: the same slots GradientTile uses, so a saver's
    // backdrop and its aurora change on the same frames and the render loop
    // sleeps between them (a FrameAnimation skipping frames kept it drawing at
    // the display's rate). A step is never negative and at most 0.25 s, so a
    // jump of the wall clock can't run it backwards. Uncapped: every frame.
    // Everything that eases moves on those ticks too.
    // The clock starts from the wall clock, within the hour
    // (Component.onCompleted): each showing opens on a different curtain, and
    // the time stays small enough for the shader's 32-bit floats to step evenly.
    property real _time: 0
    property real _reveal: intro ? 0 : 1
    property real _appear: 1               // the fade-in, when there's no intro
    readonly property real _shownReveal: animated ? 1 - Math.pow(1 - _reveal, 3) : 1
    function _advance(step) {
        const dt = Math.max(0, Math.min(step, 0.25))
        _time += dt * speed
        _retarget(dt)
        if (_lightProgress < 1) {
            _lightProgress = Math.min(1, _lightProgress + dt / 0.6)
            _light = _lightFrom + ((lightMode ? 1 : 0) - _lightFrom) * _ease(_lightProgress)
        }
        if (_appear < 1) _appear = Math.min(1, _appear + dt / 1.2)
        if (_reveal < 1) _reveal = Math.min(1, _reveal + dt / 2.4)
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
            aurora._advance((now - aurora._last) / 1000)
            aurora._last = now
            aurora._arm(false)
        }
    }
    FrameAnimation {
        id: clock
        running: aurora.playing && aurora.maxFps <= 0
        onTriggered: aurora._advance(clock.frameTime)
    }

    // The clock stopped (hidden, idle, Animated tiles off): colours and light
    // mode take their new look at once. The fade-in and intro wait to be seen,
    // unless nothing is to move at all.
    function _settle() {
        _moving = false
        _glide = 1
        _from = _to
        _take()
        _lightProgress = 1
        _light = lightMode ? 1 : 0
        if (!animated) {
            _appear = 1
            _reveal = 1
        }
    }
    onPlayingChanged: if (!playing) _settle()

    Component.onCompleted: {
        _time = (Date.now() / 1000 % 3600) * speed
        _take()
        _lightProgress = 1
        _light = lightMode ? 1 : 0
        _appear = animated && !intro ? 0 : 1
        _arm(true)
    }

    ShaderEffect {
        id: fx
        anchors.fill: parent
        visible: !aurora.fallback
        opacity: aurora.animated ? aurora._ease(aurora._appear) : 1
        blending: true
        // Rendered smaller and scaled up: the curtain has no hard edges.
        layer.enabled: aurora.resolution < 1
        layer.textureSize: Qt.size(Math.max(1, Math.ceil(width * aurora.resolution)),
                                   Math.max(1, Math.ceil(height * aurora.resolution)))
        layer.smooth: true
        // Uniforms (names match shaders/aurora.frag).
        readonly property size size: Qt.size(width, height)
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
        readonly property real lightMode: aurora._light
        readonly property real stopCount: Math.max(2, aurora._shown.length)
        readonly property real rays: Math.max(0, Math.min(1, aurora.rays))
        // The opacity the picture gets after the shader (the item's, applied
        // as the layer is drawn): the dither is scaled to it so it stays one
        // step on screen. In steps of 0.05, so a fade re-shades a few times
        // rather than every frame.
        readonly property real dim: Math.max(0.1, Math.round(aurora.opacity * 20) / 20)
        readonly property vector3d drift: Qt.vector3d(aurora._hueDrift(aurora._time, 0),
                                                      aurora._hueDrift(aurora._time, 1),
                                                      aurora._hueDrift(aurora._time, 2))
        readonly property vector4d s0: aurora._stop(0)
        readonly property vector4d s1: aurora._stop(1)
        readonly property vector4d s2: aurora._stop(2)
        readonly property vector4d s3: aurora._stop(3)
        readonly property vector4d s4: aurora._stop(4)
        fragmentShader: "qrc:/McFly/shaders/aurora.frag.qsb"
    }
}
