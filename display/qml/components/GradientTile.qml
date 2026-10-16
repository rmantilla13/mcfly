import QtQuick
import McFly
import McFly.Core

// "Poster glow" background for the highlight tiles: Home's member progress
// tiles, the assistant card and Dinner, and the Rewards balance. Dense lists
// stay on plain cards.
//
// A luminous pastel mesh gradient with one or two frosted-glass rings that
// drift slowly across it, blurred into the gradient rather than outlined, under
// a fine film grain. One ShaderEffect pass (gradient, glass, blur, grain and
// the antialiased rounded corners all happen in shaders/gradienttile.frag: no
// layers, blur passes or masks). Children go on top.
//
//   GradientTile {
//       baseColor: member.color          // or colors: [Theme.glowBlue, ...]
//       active: screen.shown             // false while its page is hidden
//       seed: index                      // tiles drift out of step
//       Label { color: parent.ink; ... } // ink/inkMuted are picked to read on it
//   }
//
// The palette comes from one base color: its hue, two analogous hues (about
// +27 and -31 degrees) and a soft near-white highlight, mapped to pastel
// lightness by day and to deep, desaturated tones at night. `colors` (3-4)
// uses those hues instead, mapped the same way so the tiles stay a family.
//
// Motion: the rings and colour fields drift on orbits made of three circles
// turning at incommensurate rates (1 : -1.618 : 2.718, and a base rate of
// their own each), so nothing ever stops dead or swings back like a
// pendulum, and the picture never repeats. `period` sets the pace: about one
// time round, scaled 0.85-1.15x by seed so tiles never line up. The paths
// are worked out here, once per update, and handed to the shader as points:
// no per-pixel trigonometry. The clock starts from the wall clock
// (a screen saver rebuilt each time it comes up never opens on the same
// picture) and only ticks while the tile can be seen (its page is showing,
// the screen saver is down, the window is up) and Settings → Animated tiles
// is on; it resumes where it stopped.
Item {
    id: tile

    // ---- Color
    property color baseColor: Theme.accent
    property var colors: []            // optional: 3-4 source colors instead of baseColor
    property bool dark: Theme.dark     // night look: deep, dim, slower
    property int moodFade: Theme.moodFade   // how long `dark` takes to come in (a Dark mode tap: Theme.themeFade)
    // How far into the night look, 0..1. It follows `dark`; bind it instead
    // to bring the night in on a clock of your own (the ambient saver's dusk).
    property real darkness: _dkEase

    // ---- Shape and glass
    property real radius: Theme.radius
    property int rings: 2              // 0, 1 or 2 frosted-glass rings
    property real ringScale: 1.0       // ring size multiplier
    property real ringBias: 0.72       // 0..1, where the rings live horizontally
    property real blur: 1.0            // 0 = crisp glass rings, 1 = rings blurred into the gradient
    property real grain: 0.035         // static film grain, for texture (0 = off); 70% at night,
                                       // where the same noise reads stronger on dark tones

    // ---- Motion
    property bool animated: Device.animatedTiles   // off: frozen where it is
    property bool active: true         // false while the tile's page isn't showing
    property real seed: 0              // per-tile variation (layout mirror + phase)
    property int period: 48000         // ms per orbit of the drift, before the seed's 0.85-1.15x
    // ---- Cost
    // The share of its physical pixels the shader runs at, scaled up after.
    // 1 for tiles; a full-screen one (the savers, setup) at 0.5 shades a
    // quarter of the pixels and loses nothing: the picture is soft, its
    // corners square. Its grain is then a texel, smoothed as it is scaled
    // up: softer, but still dithering the gradient.
    property real resolution: 1.0
    property int maxFps: Theme.motionFps  // motion updates per second (0 = every frame); slow
                                          // drift needs no more, and it halves GPU work while
                                          // nothing else on screen moves

    // ---- Read-only helpers for content on top
    readonly property color ink: _mixc(_inkL, _inkD, _inkDk)            // titles, numbers
    readonly property color inkMuted: _mixc(_mutedL, _mutedD, _inkDk)   // secondary text
    readonly property color strong: _mixc(_strongL, _strongD, _inkDk)   // fills, icons
    readonly property color glassFill: Qt.rgba(1, 1, 1, 0.50 - 0.42 * _dk)
    readonly property color glassStroke: Qt.rgba(1, 1, 1, 0.85 - 0.65 * _dk)
    // Tiles stop while the screen is idle; a screen saver's own backdrop opts
    // back in (and still stops once the panel is off).
    property bool whileIdle: false
    readonly property bool playing: animated && active && visible && (whileIdle ? !Device.screenOff : !Device.idle)
                                    && width > 0 && height > 0 && !fallback && _windowShown
    // Software renderer, or a shader that failed to load: a plain two-stop gradient.
    readonly property bool fallback: GraphicsInfo.api === GraphicsInfo.Software
                                     || fx.status === ShaderEffect.Error

    default property alias content: holder.data

    // ------------------------------------------------------------------
    // Internals

    readonly property bool _windowShown: Window.window !== null
                                         && Window.visibility !== Window.Hidden
                                         && Window.visibility !== Window.Minimized

    readonly property real _dk: _clamp(darkness, 0, 1)
    // The ink turns from dark to light quickly in the middle of the fade,
    // where the tile is mid-tone, so text never sits grey on grey for long
    // (the ambient saver's dusk takes a minute).
    readonly property real _inkDk: {
        const x = _clamp((_dk - 0.44) / 0.12, 0, 1)
        return x * x * (3 - 2 * x)
    }
    // `dark` eases in over moodFade, or quickly when the Dark mode setting
    // flipped it. Which of the two it was is only settled once Theme has seen
    // the change too, hence the callLater.
    property real _dkEase: 0
    onDarkChanged: Qt.callLater(tile._fadeDark)
    function _fadeDark() {
        dkFade.stop()
        dkFade.duration = Math.min(tile.moodFade, Theme.paletteFade)
        dkFade.to = tile.dark ? 1 : 0
        dkFade.start()
    }
    NumberAnimation { id: dkFade; target: tile; property: "_dkEase"; easing.type: Easing.InOutSine }

    // A new base color (another project, another story) eases in instead of
    // snapping. Not while the palette fades: an accent-coloured tile then
    // moves with the rest of the screen instead of chasing it 800 ms behind.
    property color _base: baseColor
    Behavior on _base {
        enabled: !Theme.fading
        ColorAnimation { duration: 800; easing.type: Easing.InOutSine }
    }

    function _clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
    function _wrap(h) { return h - Math.floor(h) }
    function _hsl(c) {
        const k = Qt.lighter(c, 1.0)   // accepts color values and strings
        let h = k.hslHue, s = k.hslSaturation
        if (h < 0) { h = 0; s = 0 }
        return { h: h, s: s, l: k.hslLightness }
    }
    function _mixc(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
    }
    // Saturation held between lo and hi, except that a near-grey stays near
    // grey, eased in over s 0..0.24 rather than switched: a colour the
    // palette fades through grey (dawn's amber to day's blue) comes back
    // gradually instead of snapping to full strength mid-fade.
    function _ramp(s, lo, hi) {
        const k = _clamp(s / 0.24, 0, 1)
        return s + (_clamp(s, lo, hi) - s) * k * k * (3 - 2 * k)
    }
    // Pastel saturation: lively but never neon; greys stay grey.
    function _sat(s) { return _ramp(s, 0.38, 0.78) }

    // Source hues: [main, analogous +, analogous -, highlight]. `nh` is the
    // hue used at night: a narrower spread reads calmer (and keeps warm
    // tiles from drifting into olive when they get dark).
    readonly property var _src: {
        if (colors && colors.length >= 3) {
            const c = colors.map(x => _hsl(x))
            if (c.length < 4) c.push({ h: _wrap(c[0].h + 0.03), s: c[0].s * 0.7, l: 0.95 })
            return c
        }
        const b = _hsl(_base)
        return [ { h: b.h,                s: b.s },
                 { h: _wrap(b.h + 0.075), s: b.s * 0.95, nh: _wrap(b.h + 0.03) },
                 { h: _wrap(b.h - 0.085), s: b.s * 0.90, nh: _wrap(b.h - 0.035) },
                 { h: _wrap(b.h + 0.03),  s: b.s * 0.70, nh: b.h } ]
    }
    function _nh(i) { return _src[i].nh !== undefined ? _src[i].nh : _src[i].h }
    // Day: luminous pastels. Night: deep, desaturated, a touch of the hue.
    readonly property var _light: [
        Qt.hsla(_src[0].h, _sat(_src[0].s),        0.79, 1),
        Qt.hsla(_src[1].h, _sat(_src[1].s),        0.83, 1),
        Qt.hsla(_src[2].h, _sat(_src[2].s),        0.76, 1),
        Qt.hsla(_src[3].h, _sat(_src[3].s) * 0.8,  0.94, 1)
    ]
    readonly property var _darkp: [
        Qt.hsla(_nh(0), _sat(_src[0].s) * 0.55, 0.19, 1),
        Qt.hsla(_nh(1), _sat(_src[1].s) * 0.50, 0.22, 1),
        Qt.hsla(_nh(2), _sat(_src[2].s) * 0.50, 0.15, 1),
        Qt.hsla(_nh(3), _sat(_src[3].s) * 0.45, 0.27, 1)
    ]
    readonly property var _pal: [
        _mixc(_light[0], _darkp[0], _dk), _mixc(_light[1], _darkp[1], _dk),
        _mixc(_light[2], _darkp[2], _dk), _mixc(_light[3], _darkp[3], _dk)
    ]
    // The colour fields for the shader. The three main ones in OKLCh (L, C,
    // hue), the hues unwrapped one to the next, so the shader's blend between
    // them keeps their chroma and goes the short way round the hue circle:
    // blue to coral passes through rose, not grey. A grey (chroma under
    // 0.02) borrows its neighbour's hue, more of it the greyer it is, so a
    // field fading through grey never flips hue in one step. The chain
    // starts from the fields' mean hue. The tint (field 2) and the highlight
    // in OKLab.
    readonly property var _lch: {
        const lab = [Theme.oklab(_pal[0]), Theme.oklab(_pal[1]), Theme.oklab(_pal[2])]
        let previous = Math.atan2(lab[0][2] + lab[1][2] + lab[2][2], lab[0][1] + lab[1][1] + lab[2][1])
        return lab.map(v => {
            const chroma = Math.hypot(v[1], v[2])
            let turn = Math.atan2(v[2], v[1]) - previous
            turn -= 2 * Math.PI * Math.round(turn / (2 * Math.PI))   // the short way round
            const k = _clamp(chroma / 0.02, 0, 1)
            previous += turn * k * k * (3 - 2 * k)
            return Qt.vector4d(v[0], chroma, previous, 0)
        })
    }
    function _labv(c) { const v = Theme.oklab(c); return Qt.vector4d(v[0], v[1], v[2], 0) }

    readonly property real _h: _src[0].h
    readonly property real _s: _src[0].s
    readonly property color _inkL:    Qt.hsla(_h, Math.min(_s, 0.45), 0.15, 1)
    readonly property color _inkD:    Qt.hsla(_h, Math.min(_s, 0.25), 0.96, 1)
    readonly property color _mutedL:  Qt.hsla(_h, Math.min(_s, 0.38), 0.26, 1)
    readonly property color _mutedD:  Qt.hsla(_h, Math.min(_s, 0.25), 0.87, 1)
    readonly property color _strongL: Qt.hsla(_h, _ramp(_s, 0.40, 0.62), 0.42, 1)
    readonly property color _strongD: Qt.hsla(_h, _ramp(_s, 0.40, 0.62), 0.72, 1)

    // Drift clock: seconds of drift as a plain double that never wraps,
    // started from the wall clock; night runs a little slower. Capped
    // (maxFps > 0), a Timer wakes on wall-clock slots of 1/maxFps s, the same
    // slots for every tile, sky, aurora and glow, so they all change on the
    // same frames, and in between the render loop sleeps. (A FrameAnimation
    // that skipped frames kept it drawing at the display's rate all the
    // same: 10 updates a second cost 60 full-screen frames.) A
    // step is never negative and at most 0.25 s, so a jump of the wall clock
    // can't throw the drift backwards or far ahead. Uncapped: every frame.
    readonly property real _period: period * (0.85 + 0.30 * _wrap(seed * 0.618034 + 0.3))
    property real _t: 0
    function _advance(dt) { _t += Math.max(0, Math.min(dt, 0.25)) * (1 - 0.35 * _dk) }
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
            tile._advance((now - tile._last) / 1000)
            tile._last = now
            tile._arm(false)
        }
    }
    FrameAnimation {
        running: tile.playing && tile.maxFps <= 0
        onTriggered: tile._advance(frameTime)
    }

    Component.onCompleted: {
        _t = (Date.now() / 1000) % 1000000
        _dkEase = dark ? 1 : 0
        _arm(true)
    }

    // A slow wobble: three sines at incommensurate rates. Never repeats.
    function _drift(u, a) {
        return 0.62 * Math.sin(u + a) + 0.26 * Math.sin(1.618034 * u + 2.1 + 1.3 * a)
             + 0.12 * Math.sin(2.718282 * u + 0.7 + 2.9 * a)
    }
    // An orbit that never closes: a main circle carrying two smaller ones,
    // turning at incommensurate rates (1 : -1.618 : 2.718). The main circle
    // is faster than the other two together, so the point never stops or
    // doubles back the way a sine's turn-around does, and the path never
    // repeats. [x, y] within about 1.2 of the centre; `dir` picks which way
    // round it goes.
    function _orbit(u, a, dir) {
        const t1 = u + a, t2 = -1.618034 * u + 2.1 + 1.3 * a, t3 = 2.718282 * u + 0.7 + 2.9 * a
        return [0.86 * Math.cos(t1) + 0.26 * Math.cos(t2) + 0.10 * Math.cos(t3),
                dir * (0.86 * Math.sin(t1) + 0.26 * Math.sin(t2) + 0.10 * Math.sin(t3))]
    }
    // The rings and the colour fields at drift time `t`, in logical px: the
    // layout the shader used to work out per pixel, each loop of the old
    // clock now an orbit at a rate of its own.
    readonly property var _geo: {
        const w = width, h = height, s = seed
        const u = 2 * Math.PI * _t / (_period / 1000)
        const flip = _wrap(s * 0.618034) >= 0.5          // mirror the layout on half the seeds
        const R1 = ringScale * Math.min(0.40 * w, 1.05 * h) * (1 + 0.02 * _drift(0.37 * u, 4.2 + s))
        const bias = flip ? 1 - ringBias : ringBias
        const hx = w * bias, hy = h * 0.42
        const side = flip ? 1 : -1                       // ring 2 sits toward the tile centre
        const ax = 0.30 * R1 + 0.05 * w                  // drift reach
        const o1 = _orbit(u, 2.1 * s, 1)
        const o2 = _orbit(0.890899 * u, 1.3 * s + 1.9, -1)
        const f0 = _orbit(0.793701 * u, s, 1)
        const f1 = _orbit(1.090508 * u, 2.3 * s + 0.7, -1)
        const f2 = _orbit(0.931298 * u, 1.1 * s + 3.1, 1)
        const f3 = _orbit(1.259921 * u, 3.1 * s + 1.6, -1)
        return {
            r1: R1,
            r1c: Qt.vector2d(hx + ax * o1[0], hy + 0.22 * R1 * o1[1]),
            r2c: Qt.vector2d(hx + 0.55 * side * R1 + ax * o2[0], hy + 0.62 * R1 + 0.26 * R1 * o2[1]),
            b0: Qt.vector2d(w * ((flip ? 0.90 : 0.10) + 0.10 * f0[0]), h * (0.10 + 0.18 * f0[1])),
            b1: Qt.vector2d(w * ((flip ? 0.10 : 0.90) + 0.12 * f1[0]), h * (0.30 + 0.20 * f1[1])),
            b2: Qt.vector2d(w * (0.45 + 0.18 * f2[0]), h * (1.00 + 0.15 * f2[1])),
            b3: Qt.vector2d(w * ((flip ? 0.38 : 0.62) + 0.20 * f3[0]), h * (0.62 + 0.22 * f3[1]))
        }
    }

    readonly property real _screenDpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
    readonly property bool _reduced: resolution > 0 && resolution < 1
    ShaderEffect {
        id: fx
        anchors.fill: parent
        visible: !tile.fallback
        // Run smaller and scaled up when asked (`resolution`): the texture's
        // pixel ratio is then the shader's, so edges and grain are a texel.
        // Only then: a layer that changes asks Qt for one more frame after
        // it, so a tile caching its own 30 updates a second would draw 60.
        layer.enabled: tile._reduced
        layer.textureSize: Qt.size(Math.max(1, Math.ceil(width * dpr)), Math.max(1, Math.ceil(height * dpr)))
        layer.smooth: true
        // Uniforms (names match shaders/gradienttile.frag).
        readonly property size size: Qt.size(width, height)
        readonly property real radius: Math.min(tile.radius, width / 2, height / 2)
        readonly property real dpr: tile._reduced ? tile._screenDpr * tile.resolution : tile._screenDpr
        readonly property real rings: tile.rings
        readonly property real r1: tile._geo.r1
        readonly property real glass: 1.0 - 0.65 * tile._dk
        readonly property real grain: tile.grain * (1.0 - 0.3 * tile._dk)
        readonly property real soft: tile.blur
        readonly property vector2d r1c: tile._geo.r1c
        readonly property vector2d r2c: tile._geo.r2c
        readonly property vector2d b0: tile._geo.b0
        readonly property vector2d b1: tile._geo.b1
        readonly property vector2d b2: tile._geo.b2
        readonly property vector2d b3: tile._geo.b3
        readonly property vector4d lch0: tile._lch[0]
        readonly property vector4d lch1: tile._lch[1]
        readonly property vector4d lch2: tile._lch[2]
        readonly property vector4d tint: tile._labv(tile._pal[2])
        readonly property vector4d hilite: tile._labv(tile._pal[3])
        readonly property color rimColor: Qt.rgba(1, 1, 1, 0.80 - 0.35 * tile._dk)
        fragmentShader: "qrc:/McFly/shaders/gradienttile.frag.qsb"
    }

    Rectangle {
        anchors.fill: parent
        visible: tile.fallback
        radius: fx.radius
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: tile._pal[0] }
            GradientStop { position: 1; color: tile._pal[1] }
        }
    }

    Item {
        id: holder
        anchors.fill: parent
    }
}
