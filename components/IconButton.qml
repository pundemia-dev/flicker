import QtQuick

// Round/rounded Tabler-glyph button (capture toolbar, panels, recording
// actions). A small fading white rim (GlowRim) keeps it readable on dark
// content; hover lightens, `checked` takes the accent, press pops the
// scale on a spring.
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
    signal clicked

    radius: height / 2
    color: root.checked ? root.accent : (ma.containsMouse && !root.disabled ? root.hoverBg : root.bg)
    opacity: root.disabled ? 0.4 : 1
    scale: ma.pressed && !root.disabled ? 0.9 : 1
    Behavior on scale { Spring { stiffness: 6; damp: 0.4; eps: 0.002 } }

    GlowRim {
        radius: root.radius
        color: root.theme.buttonGlow
        spread: root.theme.buttonGlowWidth
        peakAlpha: root.theme.buttonGlowAlpha
        rings: root.theme.buttonGlowRings
    }

    Text {
        anchors.centerIn: parent
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
