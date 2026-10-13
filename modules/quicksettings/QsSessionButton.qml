import QtQuick
import "../../components"

// Session menu button in the top-right corner, in the tab rail's column
// (outside the card grid): a small disc with the power glyph; tap opens
// the session module.
Item {
    id: root
    required property var cfg
    required property var theme
    property var frost: null
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
    }

    Icon {
        anchors.centerIn: parent
        text: "" // tabler power
        font.family: root.theme?.iconFamily ?? "tabler-icons"
        iconSize: root.cfg.sessionIconSize
        iconColor: root.theme?.islandFg ?? "#FFFFFF"
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
