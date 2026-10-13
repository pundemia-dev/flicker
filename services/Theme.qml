import QtQuick
import "../components"
import "../config"

QtObject {
    readonly property color islandBg: "#000000"
    readonly property color islandFg: "#E9ECF1"
    // 1px rim over the island edge (DMS approach): masks the zone where the
    // hard compositor blur mask diverges from the smooth painted corner.
    readonly property color islandRim: "#26FFFFFF"
    readonly property int islandRimWidth: 1
    readonly property color minimalBg: "#8D939A"
    readonly property real minimalOpacity: 0.35
    readonly property color subtleFg: "#B9C0CB"
    readonly property color accentRed: "#E4483E"
    readonly property color accentGreen: "#3DBD4E"
    readonly property color accentYellow: "#D8BE52"
    readonly property color accentOrange: "#E58B4D"
    readonly property color waveColor: "#A8C1FF"
    // Dictation wave while the backend is (re)starting and no model is
    // loaded yet: neutral grey instead of the live blue.
    readonly property color waveDim: "#6E7683"
    readonly property color arcTrack: "#6E7681"
    readonly property color arcGlow: "#2E000000"
    readonly property color islandHalo: "#01FFFFFF"
    // Dashboard cards (dark widgets on the true-black island body).
    readonly property color cardBg: "#1C1C1E"
    readonly property color cardTrack: "#2C2C2E"
    readonly property color cardDim: "#99EBEBF5"
    // Wallpaper accent (services/Wallpaper, launcher.wallpapers
    // .accentFromWallpaper): matugen's primary at accentTone of the current
    // wallpaper; transparent = off → the stock blues below.
    property color wallAccent: "transparent"
    readonly property bool wallAccentOn: wallAccent.a > 0
    // Both accents spring to the new colour (launcher.wallpapers
    // .accentStiffness/accentDamping) instead of jumping.
    readonly property SpringColor cardBlueSpring: SpringColor {
        target: wallAccentOn ? wallAccent : "#0F7CEC"
        stiffness: Config.data.launcher?.wallpapers?.accentStiffness ?? 2
        damping: Config.data.launcher?.wallpapers?.accentDamping ?? 0.6
    }
    readonly property SpringColor qsBlueSpring: SpringColor {
        target: wallAccentOn ? wallAccent : "#017EFC"
        stiffness: Config.data.launcher?.wallpapers?.accentStiffness ?? 2
        damping: Config.data.launcher?.wallpapers?.accentDamping ?? 0.6
    }
    readonly property color cardBlue: cardBlueSpring.value
    readonly property color batteryGood: "#59D67A"
    readonly property color batteryWarn: "#E7C45A"
    readonly property color batteryLow: "#E35D5D"
    // Quick Settings (iOS Control Center): accents of active controls,
    // the icon disc of inactive wide/large toggles, slider fill.
    readonly property color qsBlue: qsBlueSpring.value
    readonly property color qsIndigo: "#5E5CE6"
    readonly property color qsGreen: "#38C65A"
    readonly property color qsOrange: "#FF9F0A"
    readonly property color qsYellow: "#FFCC00"
    readonly property color qsDisc: "#3A3A3C"
    // Session menu selection plate (darker than qsDisc, user).
    readonly property color sessionPlate: "#242426"
    // QS card surface (card bg + slider track): black, user (Oct 2026).
    readonly property color qsCardBg: "#000000"
    // Launcher: hairline between the search row and the results.
    readonly property color launcherDivider: "#2EFFFFFF"
    // Wallpaper carousel: caption shade (bottom of the centre card) and the
    // GIF/VIDEO badge.
    readonly property color wallCaptionShade: "#B3000000"
    readonly property color wallBadge: "#59FFFFFF"
    // Wallpaper settings panel: focused row highlight inside a card.
    readonly property color wallSettingsFocus: "#17FFFFFF"
    // Dark icon tiles (the glyph carries the colour) and the cards' light
    // rim: top edge round both top corners, bottom edge half way round.
    readonly property color wallSettingsIconTop: "#2C2C2F"
    readonly property color wallSettingsIconBottom: "#111113"
    readonly property color wallSettingsIconRimTop: "#40FFFFFF"
    readonly property color wallSettingsIconRimBottom: "#1AFFFFFF"
    // The same tile on buttons (components/IconTile, capture): corner radius
    // as a fraction of the size, hover veil, and a tinted tile (checked /
    // accent) as lighter → darker of its colour.
    readonly property real iconTileRadius: 0.28
    readonly property color iconTileHover: "#14FFFFFF"
    readonly property real iconTileTintLighter: 1.15
    readonly property real iconTileTintDarker: 1.35
    // Drawn event glyphs (indicators/*Glyph.qml): the tile rim, stronger —
    // on a light fill (yellow pacman) the tile alphas vanished.
    // Drawn event glyphs: Apple-ish white device bodies, dark detail ink.
    readonly property color glyphDeviceTop: "#F5F6F8"
    readonly property color glyphDeviceBottom: "#A9AFB9"
    readonly property color glyphInk: "#16171B"
    // Focus / Do Not Disturb (moon glyph + event text).
    readonly property color focusPurple: "#8A7CF5"
    // Keyboard pill (modules/keyboard): background without a wallpaper
    // accent; ink by background luminance (dark on light, light on dark).
    readonly property color keyboardPillBg: "#E5E5EA"
    readonly property color keyboardPillInkDark: "#1C1C1E"
    readonly property color keyboardPillInkLight: "#FFFFFF"
    // Caffeine event: coffee (CoffeeGlyph liquid + the event text).
    readonly property color coffee: "#C8915A"
    // Shazam: card tint while listening + the event glyph/text.
    readonly property color shazam: "#0088FF"
    // Timer (modules/timer, bar ring): iOS Clock orange; paused progress
    // greys out; secondary labels; buttons = tinted discs (start green,
    // cancel red, pause grey).
    readonly property color timerAccent: "#FF9F0A"
    // Ruler tick passing the triangle flashes to this (then back).
    readonly property color timerTickFlash: "#FFF4D6"
    readonly property color timerTickDim: "#6B4307"
    readonly property color timerPaused: "#8E8E93"
    readonly property color timerTrack: "#2EFFFFFF"
    readonly property color timerDim: "#8E8E93"
    readonly property color timerButton: "#3A3A3C"
    readonly property color timerStartDisc: "#3D2A0A"
    readonly property color timerCancelDisc: "#4D1A17"
    readonly property color timerCancelInk: "#FF453A"
    readonly property color glyphRimTop: "#8CFFFFFF"
    readonly property color glyphRimBottom: "#40FFFFFF"
    readonly property color wallSettingsRimTop: "#33FFFFFF"
    readonly property color wallSettingsRimBottom: "#17FFFFFF"
    // Frosted body (QS / notification center over the compositor blur):
    // grey #A2A2A2 at 0.235 — fitted to iOS 18 Control Center samples.
    readonly property color frostBody: "#3CA2A2A2"
    // Frosted button surface, straight on the blur (the tint is knocked
    // out under it): #1C1C1C at 0.435 = fit of the samples (wall·0.565+12).
    readonly property color frostButton: "#6F1C1C1C"
    // Teleprompter body over the compositor blur (frost path with this
    // tint instead of frostBody): dark glass, white text stays readable
    // over bright windows. Read words / notes / reading-line marker. Text
    // colours stay OPAQUE: they go into rich-text CSS (no alpha there).
    readonly property color prompterBody: "#990B0B0D"
    readonly property color prompterRead: "#6F7279"
    readonly property color prompterCurrent: "#FFFFFF"
    readonly property color prompterAhead: "#ECEDF1"
    readonly property color prompterNote: "#8FA3D6"
    readonly property color prompterNoteRead: "#4E5872"
    readonly property color prompterMarker: "#A8C1FF"
    readonly property string monoFamily: "monospace"
    // QS edit mode: card rim blinks clear -> darker than the card surface
    // (the frosted button #6F1C1C1C) and back (fade).
    readonly property color qsEditRim: "#00000000"
    readonly property color qsEditRimDim: "#B3000000"
    readonly property color qsFill: "#F8F8F6"
    readonly property color qsOnFill: "#1C1C1E"
    // Slider card glyphs (both over the track and inside the fill).
    readonly property color qsVolumeIcon: "#32ADE6"
    readonly property color qsBrightnessIcon: "#FDC818"
    readonly property int fontSizeClock: 14
    readonly property int fontSizeBody: 12
    readonly property int fontSizeIndicator: 11
    readonly property int fontSizeTiny: 10
    // Global shell font (otf-san-francisco, fc family name "SF Pro Display").
    // Applied by default in components/Text.qml (theme-less, references the
    // same family literally); TextInputs set it themselves.
    readonly property string fontFamily: "SF Pro Display"
    // Icon glyph font (fc family "tabler-icons"; the filled media-control set
    // lives in the U+F6xx plane: prev f697 pause f690 play f691 next f696).
    readonly property string iconFamily: "tabler-icons"
    // Nerd Font glyphs (event indicators: pacman / AUR, like show_updates).
    readonly property string nerdIconFamily: "JetBrainsMono Nerd Font"
    // Capture overlay: screen dim, crosshair and selection frame.
    readonly property color captureDim: "#000000"
    readonly property color captureCross: "#E9ECF1"
    readonly property color captureSelection: "#E9ECF1"
    // Barely-there light glow around buttons (components/GlowRim) so they
    // read on dark content: total spread px, 1px rings, innermost alpha.
    // Keep the alpha tiny — at ~0.2 it reads as an outline (user).
    readonly property color buttonGlow: "#FFFFFF"
    readonly property real buttonGlowWidth: 6
    readonly property int buttonGlowRings: 6
    readonly property real buttonGlowAlpha: 0.05
}
