import QtQuick
import "../../components"

// Capsule text button of the polkit prompt (Отмена / Подтвердить).
Rectangle {
    id: root
    required property var theme
    required property var cfg
    property string label
    property color base: root.theme.cardBg
    signal clicked

    height: root.cfg.buttonHeight
    width: Math.max(root.cfg.buttonMinWidth, labelText.implicitWidth + root.height)
    radius: height / 2
    color: ma.pressed ? Qt.darker(root.base, 1.25) : ma.containsMouse ? Qt.lighter(root.base, 1.2) : root.base
    opacity: root.enabled ? 1 : 0.45
    Behavior on opacity { Spring { eps: 0.01 } }

    Text {
        id: labelText
        anchors.centerIn: parent
        text: root.label
        color: root.theme.islandFg
        font.family: root.theme.fontFamily
        font.pixelSize: root.cfg.fontSize
        font.weight: Font.DemiBold
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
