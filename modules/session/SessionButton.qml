import QtQuick
import "../../components"

// One session action: a bare glyph (the module draws ONE selection plate
// that springs between buttons). Idle = dimmed and a touch smaller,
// selected = full white at full size, armed (waiting for the confirming
// press; the plate turns red) = a pulse. Hover selects (the module owns the
// index), a press shrinks the glyph.
Item {
    id: root
    required property var theme
    required property var cfg
    property string glyph: ""
    property bool selected: false
    property bool armed: false
    signal hovered
    signal clicked

    width: root.cfg.buttonSize
    height: root.cfg.buttonSize

    SpringColor {
        id: ink
        target: Qt.rgba(root.theme.islandFg.r, root.theme.islandFg.g, root.theme.islandFg.b, root.selected || root.armed ? 1 : root.cfg.idleOpacity)
        stiffness: 4
        damping: 0.7
    }

    Text {
        id: glyphText
        anchors.centerIn: parent
        text: root.glyph
        color: ink.value
        font.family: root.theme.iconFamily
        font.pixelSize: root.cfg.iconSize
        renderType: Text.CurveRendering
        property real base: ma.pressed ? 0.85 : root.selected || root.armed ? 1 : root.cfg.idleScale
        Behavior on base { Spring { stiffness: 6; damp: 0.45; eps: 0.002 } }
        scale: base * bump.value
    }

    // Armed: the glyph bumps once (GlyphBump = the volume-icon pulse).
    GlyphBump { id: bump }
    onArmedChanged: if (root.armed)
        bump.bump()

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.hovered()
        onClicked: root.clicked()
    }
}
