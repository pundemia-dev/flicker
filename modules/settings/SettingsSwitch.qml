import QtQuick
import "../../components"

// iOS switch: the track tint springs green, the knob slides (stretches a
// little while pressed, like iOS). Clicks toggle; `toggled` reports.
Rectangle {
    id: root
    required property var theme
    property bool checked: false
    signal toggled(bool checked)

    width: 51
    height: 31
    radius: height / 2
    color: tint.value

    SpringColor {
        id: tint
        target: root.checked ? root.theme.qsGreen : root.theme.settingsPressed
        stiffness: 5
        damping: 0.6
    }

    Rectangle {
        readonly property real grow: area.pressed ? 6 : 0
        y: 2
        width: root.height - 4 + grow
        height: root.height - 4
        radius: height / 2
        x: root.checked ? root.width - width - 2 : 2
        color: root.theme.islandFg
        Behavior on x { Spring { stiffness: 6; damp: 0.5 } }
        Behavior on width { Spring { stiffness: 6; damp: 0.6 } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
