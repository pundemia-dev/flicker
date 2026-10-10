import QtQuick

// Round/rounded Tabler-glyph button (capture toolbar, panels, recording
// actions, stash). A small fading white rim (GlowRim) keeps it readable on
// dark content; hover lightens, `checked` takes the accent, press pops the
// scale on a spring. `tile` = the wallpaper-settings icon tile look instead
// (IconTile: dark gradient + light rim, rounded square; `tileFill` tints it).
Rectangle {
    id: root
    required property var theme
    property string glyph: ""
    property int iconSize: 16
    property bool checked: false
    property bool disabled: false
    property color fg: root.theme.islandFg
    property color bg: root.theme.cardBg
    property color hoverBg: root.theme.cardTrack
    property color accent: root.theme.cardBlue
    property bool tile: false
    property color tileFill: "transparent"
    signal clicked

    radius: root.tile ? height * root.theme.iconTileRadius : height / 2
    color: root.tile ? "transparent" : (root.checked ? root.accent : (ma.containsMouse && !root.disabled ? root.hoverBg : root.bg))
    opacity: root.disabled ? 0.4 : 1
    scale: ma.pressed && !root.disabled ? 0.9 : 1
    Behavior on scale { Spring { stiffness: 6; damp: 0.4; eps: 0.002 } }

    IconTile {
        visible: root.tile
        anchors.fill: parent
        theme: root.theme
        radius: root.radius
        fill: root.checked ? root.accent : root.tileFill
        hovered: ma.containsMouse && !root.disabled
    }

    GlowRim {
        visible: !root.tile
        radius: root.radius
        color: root.theme.buttonGlow
        spread: root.theme.buttonGlowWidth
        peakAlpha: root.theme.buttonGlowAlpha
        rings: root.theme.buttonGlowRings
    }

    Text {
        // Tile: vector glyph at the exact (fractional) centre, like the
        // wallpaper settings tiles; otherwise the pixel-snapped default.
        anchors.centerIn: root.tile ? undefined : parent
        x: (parent.width - implicitWidth) / 2
        y: (parent.height - implicitHeight) / 2
        renderType: root.tile ? Text.CurveRendering : Text.NativeRendering
        text: root.glyph
        color: root.fg
        font.family: root.theme.iconFamily
        font.pixelSize: root.iconSize
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (!root.disabled) root.clicked()
    }
}
