import QtQuick
import McFly
import McFly.Core

// The voice glow: the color-spectrum visual from the Homestead app's voice
// UI, for the quick-answer card, the Ask panel's input and the setup screen.
// Soft colour lobes rise from the bottom of a dark host with the voice, a
// layered band of light bends up into a dome in front of them, and a thin
// spectrum line runs along the rounded bottom edge. While a reply is
// prepared everything gathers into one beam that travels side to side.
// Decorative only; pair it with a text status. Drawn by
// shaders/spectrumglow.frag in one pass; a plain gradient stands in where
// shaders don't run.
//
//   SpectrumGlow {
//       level: Voice.level            // the microphone, 0..1
//       processing: AI.busy           // the beam
//       speaking: Voice.state === "speaking"
//       cornerRadius: 36
//   }
//
// Where each lobe is, how tall, how bright and what colour (mixed in OKLab)
// is worked out here once per update and handed to the shader, so per pixel
// it only draws. The lobes drift sideways at slightly uneven speeds and each
// breathes at its own rate, so the glow never settles into a loop. While it
// only idles (ambient, nothing heard, said or thought) it updates `maxFps`
// times a second; listening, speaking or thinking, every frame. With
// Settings → Animated tiles off it only answers its inputs, and stops
// updating once it has caught up with them.
Item {
    id: glow

    // ---- Input
    property real level: 0           // continuous input, 0..1
    property bool processing: false  // gather into the travelling beam
    property bool speaking: false    // no meter from the speaker: a spoken rhythm stands in
    property bool ambient: false     // a gentle steady glow (decorative hosts)
    property string kind: "screen"   // screen | input
    property real cornerRadius: 44
    property real intensity: 1.0
    property bool active: true       // false while the host isn't showing
    property bool motion: Device.animatedTiles   // off: the glow holds still (Settings → Animated tiles)
    property int maxFps: Theme.motionFps  // updates per second while it only idles (0 = every
                                          // frame): every other frame at 60 Hz, an even cadence,
                                          // and on the same frames as the tiles beside it

    // ---- Smoothed state: fast attack, slower release, eased beam.
    property real _level: 0
    property real _low: 0
    property real _mid: 0
    property real _high: 0
    property real _process: 0
    property real _time: 0
    // The spoken rhythm: a syllable's strength and how long it has left.
    property real _syllable: 0
    property real _syllableLeft: 0

    readonly property bool fallback: GraphicsInfo.api === GraphicsInfo.Software || fx.status === ShaderEffect.Error
    readonly property bool playing: active && visible && width > 0 && height > 0 && !fallback && !Device.idle
                                    && Window.window !== null && Window.visibility !== Window.Hidden
    // Something is happening: full frame rate. Only the idle glow is capped.
    readonly property bool _lively: !ambient || processing || speaking || level > 0.02 || _process > 0.01
    // Held still (motion off) and caught up with its inputs: nothing left to
    // draw, so the frame clock stops until an input changes.
    property bool _settled: false
    readonly property bool _changing: motion || !_settled
    onLevelChanged: _settled = false
    onProcessingChanged: _settled = false
    onSpeakingChanged: _settled = false
    onAmbientChanged: _settled = false
    onMotionChanged: _settled = false

    // Tuning, in units of `u`: the width for a voice screen, the height for an input.
    readonly property bool _screen: kind !== "input"
    readonly property real _u: _screen ? width : height
    readonly property real _bandWidth: _u * (_screen ? 0.04 : 0.07)
    readonly property real _bandBlur: _u * (_screen ? 0.016 : 0.03)
    readonly property real _lobeBlur: _u * (_screen ? 0.04 : 0.1)

    // Per lobe, for the shader: l = (x, top, 1/(2 sigma^2) of its width, alpha)
    // in logical px, k = (colour, weight in the band's colour). And the dome:
    // (centre x, half its width, crest height, energy).
    property vector4d _l0
    property vector4d _l1
    property vector4d _l2
    property vector4d _l3
    property vector4d _l4
    property vector4d _l5
    property vector4d _l6
    property vector4d _k0
    property vector4d _k1
    property vector4d _k2
    property vector4d _k3
    property vector4d _k4
    property vector4d _k5
    property vector4d _k6
    property vector4d _dome

    // The spectrum in OKLab, in the order the hue drifts.
    readonly property var _stops: Theme.spectrum.map(c => Theme.oklab(c))

    function _clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
    // Frame-rate independent: the same glide at 24 fps as at 60.
    function _follow(current, target, dt) {
        const rate = target > current ? 14 : 3.2
        return current + (target - current) * (1 - Math.exp(-rate * dt))
    }
    // The palette at `position` (in stops, wrapping), mixed in OKLab: green
    // to amber goes through yellow, not olive.
    function _colorAt(position) {
        const n = _stops.length
        const p = ((position % n) + n) % n
        const i = Math.floor(p), f = p - i
        const a = _stops[i], b = _stops[(i + 1) % n]
        return Theme.fromOklab([a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f])
    }
    // Speaking: the speaker sends no meter, so syllables stand in: a new
    // strength every 120-300 ms, and now and then a short gap.
    function _speech(dt) {
        _syllableLeft -= dt
        if (_syllableLeft <= 0) {
            const gap = _syllable > 0.3 && Math.random() < 0.3
            _syllable = gap ? 0.2 : 0.38 + 0.36 * Math.random()
            _syllableLeft = gap ? 0.08 + 0.12 * Math.random() : 0.12 + 0.18 * Math.random()
        }
        return _syllable
    }

    function _tick(dt) {
        if (motion)
            _time += dt
        const t = _time
        // What the lobes follow: the mic, a spoken rhythm, or a soft idle.
        let input = level
        if (speaking)
            input = motion ? _speech(dt) : 0.55
        else if (ambient)
            input = 0.5
        const low = motion ? input * (0.9 + 0.1 * Math.sin(t * 2.3)) : input
        const high = motion ? input * (0.85 + 0.15 * Math.sin(t * 5.1 + 0.8 * Math.sin(t * 1.3))) : input
        _level = _follow(_level, input, dt)
        _low = _follow(_low, low, dt)
        _mid = _follow(_mid, input, dt)
        _high = _follow(_high, high, dt)
        _process += ((processing ? 1 : 0) - _process) * (1 - Math.exp(-2.6 * dt))
        if (!motion) {
            const target = processing ? 1 : 0
            if (Math.abs(_level - input) < 1e-3 && Math.abs(_low - low) < 1e-3 && Math.abs(_mid - input) < 1e-3
                    && Math.abs(_high - high) < 1e-3 && Math.abs(_process - target) < 1e-3) {
                _level = input; _low = low; _mid = input; _high = high; _process = target
                _settled = true
            }
        }
        _update()
    }

    function _update() {
        const w = width, h = height
        if (w <= 0 || h <= 0)
            return
        const scr = _screen, u = _u
        const restReach = scr ? 0.10 : 0.22, reach = scr ? 0.56 : 0.55
        const restBend = scr ? 0.012 : 0.03, bend = scr ? 0.115 : 0.36
        const spread = scr ? 0.5 : 0.36
        const lobeWidth = scr ? 0.24 : 0.9
        const t = _time, process = _process

        // The beam sweeps on two sines, so it never ticks like a metronome.
        const beamX = w * (0.5 + 0.3 * (0.72 * Math.sin(t * 1.3) + 0.28 * Math.sin(t * 2.11 + 1.0)))
        const energy = Math.max(_level, 0.7 * process)
        const centerX = 0.5 * w + (beamX - 0.5 * w) * process
        const halfWidth = w * (spread + (0.17 - spread) * process)
        const crest = u * (restBend + bend * energy) * (1 - process) + u * bend * 0.85 * process
        _dome = Qt.vector4d(centerX, halfWidth * 0.47, crest, energy)

        const bands = [_low, _mid, _high, _mid, _low, _high, _mid]
        const drift = t * 0.045
        const l = [], k = []
        for (let i = 0; i < 7; ++i) {
            // Along a slow conveyor, each a little ahead or behind its place.
            let flow = i / 7 + 0.05 * t + 0.035 * Math.sin(t * (0.23 + 0.071 * i) + 1.7 * i)
            flow -= Math.floor(flow)
            const s = (flow * 2 - 1) * 1.2
            const restX = 0.5 * w + s * 0.5 * w
            const edgeFade = _clamp((1.2 - Math.abs(s)) / 0.35, 0, 1)
            const band = bands[i]
            const breath = 0.025 * Math.sin(t * 0.9 * (0.8 + 0.061 * i) + 2.1 * i)
            const rd = (restX - centerX) / (halfWidth * 0.47)
            const restBell = 1 / (1 + rd * rd)
            const voiceHeight = u * (restReach + breath + reach * band) * (0.55 + 0.45 * restBell)
            const x = restX + (beamX + (i - 3) * w * 0.03 - restX) * process
            const height = voiceHeight + (u * reach * 0.8 - voiceHeight) * process
            const width = u * lobeWidth * (1 - 0.3 * process)
            const alpha = ((0.16 + 0.55 * Math.max(band, _level * 0.6)) * edgeFade * (0.3 + 0.7 * restBell)) * (1 - process)
                        + 0.45 * process
            const weight = edgeFade + (1 - edgeFade) * process
            const sigma = 0.42 * width + 0.5 * _lobeBlur
            const c = _colorAt(i + drift)
            l.push(Qt.vector4d(x, h - height, 1 / (2 * sigma * sigma), alpha))
            k.push(Qt.vector4d(c.r, c.g, c.b, weight))
        }
        _l0 = l[0]; _l1 = l[1]; _l2 = l[2]; _l3 = l[3]; _l4 = l[4]; _l5 = l[5]; _l6 = l[6]
        _k0 = k[0]; _k1 = k[1]; _k2 = k[2]; _k3 = k[3]; _k4 = k[4]; _k5 = k[5]; _k6 = k[6]
    }

    Component.onCompleted: {
        _time = (Date.now() / 1000) % 10000   // a different glow each time it opens
        _update()
        _arm(true)
    }
    onWidthChanged: _update()
    onHeightChanged: _update()
    onKindChanged: _update()

    // Idling: a Timer on wall-clock slots of 1/maxFps s, the same slots the
    // tiles and the aurora keep, so anything beside it moving 10 or 20 times
    // a second changes on the same frames, and the render loop sleeps in
    // between (a FrameAnimation skipping frames kept it drawing at the
    // display's rate). Listening, speaking or thinking: every frame. A step
    // is never negative and at most 0.1 s.
    property real _last: 0
    readonly property bool _slotted: playing && _changing && !_lively && maxFps > 0
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
            glow._tick(Math.max(0, Math.min((now - glow._last) / 1000, 0.1)))
            glow._last = now
            glow._arm(false)
        }
    }
    FrameAnimation {
        running: glow.playing && glow._changing && (glow._lively || glow.maxFps <= 0)
        onTriggered: glow._tick(Math.max(0, Math.min(frameTime, 0.1)))
    }

    ShaderEffect {
        id: fx
        anchors.fill: parent
        visible: !glow.fallback
        blending: true
        // Uniforms (names match shaders/spectrumglow.frag).
        readonly property size size: Qt.size(width, height)
        readonly property real radius: glow.cornerRadius
        readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
        readonly property real intensity: glow.intensity
        readonly property real bandWidth: glow._bandWidth
        readonly property real bandBlur: glow._bandBlur
        readonly property real lobeBlur: glow._lobeBlur
        readonly property vector4d dome: glow._dome
        readonly property vector4d l0: glow._l0
        readonly property vector4d l1: glow._l1
        readonly property vector4d l2: glow._l2
        readonly property vector4d l3: glow._l3
        readonly property vector4d l4: glow._l4
        readonly property vector4d l5: glow._l5
        readonly property vector4d l6: glow._l6
        readonly property vector4d k0: glow._k0
        readonly property vector4d k1: glow._k1
        readonly property vector4d k2: glow._k2
        readonly property vector4d k3: glow._k3
        readonly property vector4d k4: glow._k4
        readonly property vector4d k5: glow._k5
        readonly property vector4d k6: glow._k6
        fragmentShader: "qrc:/McFly/shaders/spectrumglow.frag.qsb"
    }

    // No shaders (software rendering): a soft spectrum band along the bottom.
    Rectangle {
        visible: glow.fallback
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: Math.max(24, parent.height * 0.18)
        opacity: 0.6 + 0.4 * glow.level
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Theme.spectrum[0] }
            GradientStop { position: 0.3; color: Theme.spectrum[2] }
            GradientStop { position: 0.55; color: Theme.spectrum[3] }
            GradientStop { position: 0.8; color: Theme.spectrum[5] }
            GradientStop { position: 1.0; color: Theme.spectrum[6] }
        }
    }
}
