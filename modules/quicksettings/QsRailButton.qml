import QtQuick
import "../../components"

// Small disc in a corner of the tab rail's column (outside the card grid):
// session menu (power, top-right) and edit mode (plus, bottom-right; a
// check while editing). `alt` blur-fades the glyph to `altGlyph`.
Item {
    id: root
    required property var cfg
    required property var theme
    property var frost: null
    property string glyph: ""
    property string altGlyph: ""
    property bool alt: false
    signal clicked

    width: root.cfg.sessionButtonSize
    height: root.cfg.sessionButtonSize
    scale: ma.pressed ? 0.9 : 1
    Behavior on scale { Spring { stiffness: 6; damp: 0.45; eps: 0.002 } }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        readonly property color base: ma.containsMouse ? Qt.lighter(root.theme?.qsDisc ?? "#3A3A3C", 1.25) : (root.theme?.qsDisc ?? "#3A3A3C")
        color: root.frost?.layerColor(base) ?? base

        InnerShadow {
            anchors.fill: parent
            radius: parent.radius
            size: Math.round(parent.height * 0.3)
            strength: root.cfg.innerShadowStrength ?? 0.06
        }
    }

    Repeater {
        model: [root.glyph, root.altGlyph]
        delegate: FadeBlur {
            required property string modelData
            required property int index
            anchors.fill: parent
            shown: (index === 1) === root.alt
            Icon {
                anchors.centerIn: parent
                text: parent.modelData
                font.family: root.theme?.iconFamily ?? "tabler-icons"
                iconSize: root.cfg.sessionIconSize
                iconColor: root.theme?.islandFg ?? "#FFFFFF"
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
