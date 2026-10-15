pragma Singleton
import QtQuick
import McFly.Core

// Design tokens with a dynamic, time-of-day palette.
//
// Device.mood picks one of four moods - morning (warm peach/coral), day
// (clear blue), evening (violet/rose) and night (dark) - and every color
// eases to the new palette over `moodFade`, a short shift rather than a cut.
//
// Settings → Dark mode (Device.darkMode, remembered) replaces that palette
// with one warm near-black canvas. The accent stays the day blue.
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
    property color background: p.background
    property color surface:    p.surface
    property color surfaceAlt: p.surfaceAlt
    property color sunken:     p.sunken
    property color text:       p.text
    property color textMuted:  p.textMuted
    property color divider:    p.divider
    property color accent:     p.accent
    property color accentSoft: p.accentSoft
    property color danger:     p.danger      // turned-down chores, problems
    property color warningInk: p.warningInk  // "waiting" text on an amber tint
    property color glowBlue:   p.glow[0]
    property color glowCoral:  p.glow[1]
    property color glowAmber:  p.glow[2]
    property color glowCream:  p.glow[3]

    // Motion. Pages, sheets and the screen-saver veil use `smooth`.
    // Small controls and color changes use `quick`. Ambient loops
    // (gradient-tile drift, photo-frame crossfades) stay slow on purpose.
    readonly property int quick: 100
    readonly property int smooth: 160
    // Palette and dark-mode colors. Same length as a small control fade.
    readonly property int moodFade: quick
    Behavior on background { ColorAnimation { duration: theme.moodFade } }
    Behavior on surface    { ColorAnimation { duration: theme.moodFade } }
    Behavior on surfaceAlt { ColorAnimation { duration: theme.moodFade } }
    Behavior on sunken     { ColorAnimation { duration: theme.moodFade } }
    Behavior on text       { ColorAnimation { duration: theme.moodFade } }
    Behavior on textMuted  { ColorAnimation { duration: theme.moodFade } }
    Behavior on divider    { ColorAnimation { duration: theme.moodFade } }
    Behavior on accent     { ColorAnimation { duration: theme.moodFade } }
    Behavior on accentSoft { ColorAnimation { duration: theme.moodFade } }
    Behavior on danger     { ColorAnimation { duration: theme.moodFade } }
    Behavior on warningInk { ColorAnimation { duration: theme.moodFade } }
    Behavior on glowBlue   { ColorAnimation { duration: theme.moodFade } }
    Behavior on glowCoral  { ColorAnimation { duration: theme.moodFade } }
    Behavior on glowAmber  { ColorAnimation { duration: theme.moodFade } }
    Behavior on glowCream  { ColorAnimation { duration: theme.moodFade } }

    readonly property color accentInk: "#FFFFFF"
    readonly property color success:   "#3DB37A"
    readonly property color warning:   "#F2A93B"

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
