pragma Singleton
import QtQuick
import McFly.Core

// Design tokens with a dynamic, time-of-day palette.
//
// Device.mood picks one of four moods - morning (warm peach/coral), day
// (clear blue), evening (violet/rose) and night (dark) - and every color
// drifts to the new palette over `moodFade`, a few seconds, blended in OKLab
// so a fade from amber to blue doesn't pass through grey.
//
// Settings → Dark mode (Device.darkMode, remembered) replaces that palette
// with one warm near-black canvas, over the much shorter `themeFade`: it is
// a tap, and should answer like one. The accent stays the day blue.
//
// Layout comes from two measurements Main.qml makes of the window (see
// docs/LAYOUTS.md): the tier (where the nav goes, how many columns, whether
// a detail is a pane or a pushed page) and the scale (type and radius, from
// the shorter side).
Item {
    id: theme
    visible: false

    readonly property string mood: Device.mood
    readonly property bool darkMode: Device.darkMode
    // Night, or the settings toggle: tiles and member tags use the dark treatment.
    readonly property bool dark: darkMode || mood === "night"

    readonly property var palettes: ({
        "morning": {
            background: "#F6F0E9", surface: "#FFFFFF", surfaceAlt: "#F6F0E9", sunken: "#EEE5DA",
            text: "#221C19", textMuted: "#7D736C", divider: "#E9DFD3",
            accent: "#E2725B", accentSoft: "#FBE4DC", danger: "#A8301F", warningInk: "#9A5B00",
            glow: ["#F6B94A", "#F07F5A", "#F2A7C3", "#FBE6B0"]
        },
        "day": {
            background: "#F1EFEB", surface: "#FFFFFF", surfaceAlt: "#F1EFEB", sunken: "#E9E6E0",
            text: "#1C1C1F", textMuted: "#77767B", divider: "#E4E0D9",
            accent: "#4F7CF7", accentSoft: "#E3EAFE", danger: "#B23224", warningInk: "#9A5B00",
            glow: ["#5B7CF5", "#F07F5A", "#F6B94A", "#FBE6B0"]
        },
        "evening": {
            background: "#EFEDF3", surface: "#FFFFFF", surfaceAlt: "#EFEDF3", sunken: "#E5E1EC",
            text: "#1D1B24", textMuted: "#76727F", divider: "#E1DCE8",
            accent: "#7A64E8", accentSoft: "#ECE8FD", danger: "#B33A47", warningInk: "#9A5B00",
            glow: ["#7A64E8", "#E86A92", "#F07F5A", "#F6B94A"]
        },
        "night": {
            background: "#121317", surface: "#1C1E24", surfaceAlt: "#262931", sunken: "#2C2F38",
            text: "#ECEDEF", textMuted: "#8F95A1", divider: "#30333C",
            accent: "#8EA2FF", accentSoft: "#2A3554", danger: "#FF7B6B", warningInk: "#F2A93B",
            glow: ["#3B4FB8", "#7A64E8", "#A04E78", "#6B4A2A"]
        }
    })
    // Warm near-black. Cards step up from the canvas; the accent is the day blue.
    readonly property var darkPalette: ({
        background: "#1C1814", surface: "#2A2420", surfaceAlt: "#342C26", sunken: "#3E362F",
        text: "#F6F1EB", textMuted: "#B3A69C", divider: "#6B6056",
        accent: "#4F7CF7", accentSoft: "#243056", danger: "#F2826B", warningInk: "#F2A93B",
        glow: ["#3B5BD4", "#C45A3A", "#C48A2E", "#8A7350"]
    })
    readonly property var p: darkMode ? darkPalette : (palettes[mood] || palettes["day"])

    // Animated tokens. Everything in the UI binds to these.
    property color background: _token(0)
    property color surface:    _token(1)
    property color surfaceAlt: _token(2)
    property color sunken:     _token(3)
    property color text:       _token(4)
    property color textMuted:  _token(5)
    property color divider:    _token(6)
    property color accent:     _token(7)
    property color accentSoft: _token(8)
    property color danger:     _token(9)     // turned-down chores, problems
    property color warningInk: _token(10)    // "waiting" text on an amber tint
    property color glowBlue:   _token(11)
    property color glowCoral:  _token(12)
    property color glowAmber:  _token(13)
    property color glowCream:  _token(14)

    // Motion. Pages, sheets and the screen-saver veil use `smooth`.
    // Small controls and color changes use `quick`. Ambient loops
    // (gradient-tile drift, photo-frame crossfades) stay slow on purpose.
    readonly property int quick: 100
    readonly property int smooth: 160
    // Palette changes: the Dark mode toggle, and the scheduled moods.
    readonly property int themeFade: 300
    readonly property int moodFade: 4000
    // The palette change in progress: themeFade while a Dark mode toggle
    // fades, moodFade otherwise. For things that ease along with the palette
    // on their own (GradientTile's night look).
    property int paletteFade: moodFade
    // True while the palette fades. Anything with an ease of its own on a
    // token's colour turns it off meanwhile, or it lags behind the fade.
    readonly property bool fading: paletteFadeAnim.running
    // Arriving and leaving: a card, a sheet, a row. Leaving is quicker.
    readonly property int enter: 320
    readonly property int exit: 180
    // A screen's contents settling in, staggered, once it shows.
    readonly property int revealDuration: 600
    // Ambient layers coming and going: the screen saver drifting in.
    readonly property int ambientFade: 1600
    // Something moving to a new place: a board's tiles, the "now" marker.
    readonly property int glide: 480
    // Half of a slow, calm loop (a status that needs a look breathing, a
    // fresh price's halo): in, then out again over twice this.
    readonly property int breath: 2200
    // Curves for `easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standard`.
    // `standard` for most movement; `emphasized` for an arrival that should
    // land with a little life (fast out, long settle).
    readonly property var standard: [0.2, 0, 0, 1, 1, 1]
    readonly property var emphasized: [0.05, 0.7, 0.1, 1, 1, 1]
    // The screen savers' moving backdrop: updates per second while the
    // screen is idle (docs/ARCHITECTURE.md: 10), and how long one orbit
    // of its drift takes. Slow enough that an update moves things about a pixel.
    readonly property int saverFps: 10
    readonly property int saverDrift: 110000

    // The voice glow's spectrum (SpectrumGlow): the same in every mood.
    readonly property var spectrum: ["#DB47B3", "#8F57E6", "#4280F5", "#24C2C2", "#4DC266", "#F5A83D", "#F56161"]

    // ---- Colour in OKLab: [L, a, b, alpha]. A blend in it keeps lightness
    // even and takes hues the short way, where RGB greys out (#F6B94A to
    // #5B7CF5 passes through #A99BA0).
    function oklab(c) {
        const k = Qt.lighter(c, 1.0)   // accepts colour values and strings
        const lin = x => x <= 0.04045 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4)
        const r = lin(k.r), g = lin(k.g), b = lin(k.b)
        const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
                k.a]
    }
    function fromOklab(v) {
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
                       enc(-0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S),
                       v.length > 3 ? v[3] : 1)
    }
    function mixOklab(a, b, t) {
        const x = oklab(a), y = oklab(b)
        return fromOklab(x.map((v, i) => v + (y[i] - v) * t))
    }

    // ---- The palette fade. The tokens move from what they showed to the new
    // palette along an eased 0..1 (`_fade`), in OKLab. One explicit fade
    // rather than a Behavior per token: whether Dark mode or the schedule
    // changed is known here, as the palette changes, so the length is right
    // from the first frame.
    readonly property var _keys: ["background", "surface", "surfaceAlt", "sunken", "text", "textMuted",
                                  "divider", "accent", "accentSoft", "danger", "warningInk"]
    function _flat(q) { return _keys.map(k => q[k]).concat(q.glow) }
    property var _to: null        // the palette being faded to, flattened (null until completed)
    property var _toLab: []
    property var _fromLab: []
    property real _fade: 1
    property bool _lastDark: false
    // While a new fade is set up the tokens hold what they showed, so none
    // of them passes through a half-updated state on the way.
    property var _held: null
    function _token(i) {
        if (_to === null)
            return _flat(p)[i]
        if (_held !== null)
            return _held[i]
        if (_fade >= 1)
            return _to[i]
        const a = _fromLab[i], b = _toLab[i], t = _fade
        return fromOklab([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t,
                          a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t])
    }
    Component.onCompleted: {
        _lastDark = darkMode
        _to = _flat(p)
    }
    onPChanged: {
        if (_to === null)
            return
        // From what is on screen now, mid-fade or not.
        const shown = [background, surface, surfaceAlt, sunken, text, textMuted, divider, accent,
                       accentSoft, danger, warningInk, glowBlue, glowCoral, glowAmber, glowCream]
        _held = shown
        paletteFadeAnim.stop()
        _fromLab = shown.map(c => oklab(c))
        _toLab = _flat(p).map(c => oklab(c))
        _to = _flat(p)
        _fade = 0
        paletteFade = darkMode !== _lastDark ? themeFade : moodFade
        _lastDark = darkMode
        paletteFadeAnim.duration = paletteFade
        // Started before the tokens are let go, so `fading` is already true
        // when they first move.
        paletteFadeAnim.start()
        _held = null
    }
    NumberAnimation {
        id: paletteFadeAnim
        target: theme
        property: "_fade"
        from: 0
        to: 1
        easing.type: Easing.InOutSine
        onFinished: theme.paletteFade = theme.moodFade
    }

    readonly property color accentInk: "#FFFFFF"
    readonly property color success:   "#3DB37A"
    readonly property color warning:   "#F2A93B"
    // A market up or down: saturated, so a move reads from across the room.
    // Brighter on the dark canvas, where the light pair would look dull.
    readonly property color gain: dark ? "#32E06E" : "#00B54A"
    readonly property color loss: dark ? "#FF4D4D" : "#F2262B"

    // ---- The frame: set by Main.qml from the window.
    //
    //   wide     landscape, >= 1600 wide: a TV or monitor, the 10.1" at scale 1
    //   compact  landscape, 1000-1600: the 10.1" at QT_SCALE_FACTOR 1.5 (1280x800)
    //   mini     landscape, < 1000: the 7" Touch Display (800x480)
    //   tall     portrait: the Touch Display 2 (720x1280)
    property string tier: "compact"
    // The shorter side of the window: what limits how big type can be.
    property int shortSide: 800

    readonly property bool wide: tier === "wide"
    readonly property bool mini: tier === "mini"
    readonly property bool tall: tier === "tall"
    // Everything but a wall: the long-standing "tighter" switch.
    readonly property bool compact: tier !== "wide"
    // A detail sits beside its list; otherwise it is a page pushed over it.
    readonly property bool paned: tier === "wide" || tier === "compact"
    // The nav is a rail down the left, or a bar along the bottom.
    readonly property string navMode: paned ? "rail" : "bar"
    // Pictures on pages (the 7" panel has no room for them; a saver still may).
    readonly property bool pictures: tier !== "mini"

    // ---- The scale: s below 600 px on the short side, else m.
    readonly property string scale: shortSide < 600 ? "s" : "m"
    readonly property bool small: scale === "s"

    readonly property string fontFamily: "Inter"  // falls back to the system sans if missing
    readonly property string emojiFont: "Noto Color Emoji"
    readonly property int fontXs: small ? 14 : 15
    readonly property int fontSm: small ? 16 : 18
    readonly property int fontMd: small ? 20 : 23
    readonly property int fontLg: small ? 26 : 30
    readonly property int fontXl: small ? 36 : 44
    readonly property int fontHuge: small ? 64 : compact ? 88 : 112

    readonly property int radius: small ? 24 : 28
    readonly property int radiusSm: small ? 16 : 18
    // The gutter between regions.
    readonly property int spacing: wide ? 24 : mini ? 12 : 16
    readonly property int pageMargin: wide ? 40 : compact && paned ? 24 : mini ? 16 : 20
    // Never smaller, on any panel: Mini shows fewer things, not smaller ones.
    readonly property int touchTarget: 64

    // ---- Nav
    readonly property int navWidth: navMode === "rail" ? (wide ? 124 : 100) : 0
    readonly property int navHeight: navMode === "bar" ? (tall ? 84 : 76) : 0

    // ---- Panes and fixed regions (paned tiers; the others push)
    readonly property int listWidth: wide ? 520 : 440   // Briefs' list
    readonly property int paneWidth: wide ? 440 : 380   // Markets' detail
    readonly property int heroHeight: wide ? 360 : tall ? 240 : mini ? 0 : 300
    readonly property int storyCardHeight: wide ? 280 : tall ? 290 : mini ? 88 : 250
    readonly property int quoteTileHeight: mini ? 112 : tall ? 150 : 168
    readonly property int projectCardHeight: mini ? 124 : tall ? 170 : 196
    readonly property int widgetRowHeight: wide ? 150 : mini ? 120 : 140

    // ---- Columns per grid
    readonly property int columns: wide ? 12 : paned ? 8 : 4
    readonly property int storyColumns: wide ? 4 : paned ? 3 : 2
    readonly property int quoteColumns: wide ? 3 : mini ? 3 : 2
    readonly property int metricColumns: wide ? 4 : paned ? 3 : 2
    readonly property int projectColumns: wide ? 3 : 2
    readonly property int widgetColumns: wide ? 6 : paned ? 4 : 2
    readonly property int dayColumns: wide ? 14 : paned ? 10 : 7   // 64 px cells at least
}
