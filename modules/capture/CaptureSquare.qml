import QtQuick
import "../../core"
import "../../components"
import "../../config"

// The stolen island background as the cursor bubble (pShell CursorGuide
// shape: every corner fully round except the top-left one, which points at
// the cursor) with the current mode icon. Icon arrival and mode changes go
// through ContentSwap (blur->fade). Leaves as the island (black body,
// island rim) and turns into the capture buttons' icon tile (IconTile) as it
// lands: `tileLevel` 0..1 follows the flight.
Rectangle {
    id: root
    required property var theme
    required property var cfg
    property string glyph: ""
    property color glyphColor: "white"
    property var swapKey
    property bool iconShown: false
    property real tipRadius: 0
    property real tileLevel: 0
    topLeftRadius: root.tipRadius
    // Rendered icon: switches at the ContentSwap handover, not on the mode
    // change itself (the new glyph must not pop in before the blur).
    property string shownGlyph: root.glyph
    property color shownColor: root.glyphColor

    color: root.theme.islandBg
    border.width: root.theme.islandRimWidth
    border.color: root.theme.islandRim

    IconTile {
        anchors.fill: parent
        theme: root.theme
        radius: root.radius
        topLeftRadius: root.tipRadius
        opacity: Math.max(0, Math.min(1, root.tileLevel))
        visible: opacity > 0
    }

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
            // Vector glyph at the exact centre, like the button tiles.
            x: (parent.width - implicitWidth) / 2
            y: (parent.height - implicitHeight) / 2
            renderType: Text.CurveRendering
            text: root.shownGlyph
            color: root.shownColor
            font.family: root.theme.iconFamily
            font.pixelSize: root.cfg.iconSize
        }
    }
}
