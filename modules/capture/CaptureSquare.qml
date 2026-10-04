import QtQuick
import "../../core"
import "../../config"

// The stolen island background as the cursor bubble (pShell CursorGuide
// shape: every corner fully round except the top-left one, which points at
// the cursor) with the current mode icon. Icon arrival and mode changes go
// through ContentSwap (blur->fade).
Rectangle {
    id: root
    required property var theme
    required property var cfg
    property string glyph: ""
    property color glyphColor: "white"
    property var swapKey
    property bool iconShown: false
    property real tipRadius: 0
    topLeftRadius: root.tipRadius
    // Rendered icon: switches at the ContentSwap handover, not on the mode
    // change itself (the new glyph must not pop in before the blur).
    property string shownGlyph: root.glyph
    property color shownColor: root.glyphColor

    color: root.theme.islandBg
    border.width: root.theme.islandRimWidth
    border.color: root.theme.islandRim

    ContentSwap {
        anchors.fill: parent
        showing: root.iconShown
        swapKey: root.swapKey
        surfaceRadius: root.radius
        blurMax: root.cfg.iconBlurMax
        fadeColor: root.theme.islandBg
        blurInMs: Config.data.timings.blurInMs
        fadeInMs: Config.data.timings.fadeInMs
        blurOutMs: Config.data.timings.blurOutMs
        fadeOutMs: Config.data.timings.fadeOutMs
        stageDelayMs: Config.data.timings.blurFadeDelayMs
        onCommitted: {
            root.shownGlyph = root.glyph;
            root.shownColor = root.glyphColor;
        }

        Text {
            anchors.centerIn: parent
            text: root.shownGlyph
            color: root.shownColor
            font.family: root.theme.iconFamily
            font.pixelSize: root.cfg.iconSize
        }
    }
}
