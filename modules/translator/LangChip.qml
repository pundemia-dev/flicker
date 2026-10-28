import QtQuick
import "../../components"

// Capsule button of the translator (language / engine / picker entry):
// cardBg plate, accent while `checked`, hover lightens; optional trailing
// chevron for the ones that open a picker.
Rectangle {
    id: root
    required property var theme
    property string text: ""
    property string glyph: ""
    property bool checked: false
    property bool chevron: false
    property bool subtle: false
    property real padX: 10
    property real fontSize: root.theme.fontSizeBody
    signal clicked

    implicitWidth: row.implicitWidth + root.padX * 2
    implicitHeight: 26
    radius: height / 2
    color: root.checked ? root.theme.cardBlue : (ma.containsMouse ? root.theme.cardTrack : (root.subtle ? "transparent" : root.theme.cardBg))
    scale: ma.pressed ? 0.94 : 1
    Behavior on scale { Spring { stiffness: 6; damp: 0.4; eps: 0.002 } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4
        Icon {
            visible: root.glyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.glyph
            font.family: root.theme.iconFamily
            iconSize: root.fontSize + 2
            iconColor: root.theme.islandFg
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.theme.islandFg
            font.family: root.theme.fontFamily
            font.pixelSize: root.fontSize
            font.weight: root.checked ? Font.DemiBold : Font.Medium
        }
        Icon {
            visible: root.chevron
            anchors.verticalCenter: parent.verticalCenter
            text: "" // tabler chevron-down
            font.family: root.theme.iconFamily
            iconSize: root.fontSize
            iconColor: root.theme.subtleFg
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
