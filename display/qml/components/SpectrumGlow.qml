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
    property bool motion: true

    // ---- Smoothed state: fast attack, slower release, eased beam.
    property real _level: 0
    property real _low: 0
    property real _mid: 0
    property real _high: 0
    property real _process: 0
    property real _time: 0
    property real _last: 0
    property real _tick: 0

    readonly property bool fallback: GraphicsInfo.api === GraphicsInfo.Software || fx.status === ShaderEffect.Error
    readonly property bool playing: active && visible && width > 0 && height > 0 && !fallback && !Device.idle
                                    && Window.window !== null && Window.visibility !== Window.Hidden

    function _follow(current, target, dt) {
        const rate = target > current ? 14 : 3.2
        return current + (target - current) * Math.min(1, rate * dt)
    }

    FrameAnimation {
        running: glow.playing
        onRunningChanged: if (running) glow._last = Date.now()
        onTriggered: {
            const now = Date.now()
            const dt = Math.min((now - glow._last) / 1000, 0.1)
            glow._last = now
            glow._time += dt
            glow._tick += dt
            // What the lobes follow: the mic, a spoken rhythm, or a soft idle.
            let input = glow.level
            if (glow.speaking)
                input = 0.35 + 0.35 * Math.abs(Math.sin(glow._time * 7.3)) * (0.6 + 0.4 * Math.sin(glow._time * 1.7))
            else if (glow.ambient)
                input = 0.5
            const low = input * (0.9 + 0.1 * Math.sin(glow._time * 2.3))
            const high = input * (0.7 + 0.3 * Math.abs(Math.sin(glow._time * 5.1)))
            glow._level = glow._follow(glow._level, input, dt)
            glow._low = glow._follow(glow._low, low, dt)
            glow._mid = glow._follow(glow._mid, input, dt)
            glow._high = glow._follow(glow._high, high, dt)
            glow._process += ((glow.processing ? 1 : 0) - glow._process) * Math.min(1, 2.6 * dt)
        }
    }

    ShaderEffect {
        id: fx
        anchors.fill: parent
        visible: !glow.fallback
        blending: true
        readonly property size size: Qt.size(width, height)
        readonly property real radius: glow.cornerRadius
        readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
        readonly property real time: glow._time
        readonly property real level: glow._level
        readonly property real low: glow._low
        readonly property real mid: glow._mid
        readonly property real high: glow._high
        readonly property real processing: glow._process
        readonly property real motion: glow.motion ? 1 : 0
        readonly property real kind: glow.kind === "input" ? 1 : 0
        readonly property real intensity: glow.intensity
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
            GradientStop { position: 0.0; color: "#DB47B3" }
            GradientStop { position: 0.3; color: "#4280F5" }
            GradientStop { position: 0.55; color: "#24C2C2" }
            GradientStop { position: 0.8; color: "#F5A83D" }
            GradientStop { position: 1.0; color: "#F56161" }
        }
    }
}
