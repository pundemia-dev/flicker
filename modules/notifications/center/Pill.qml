import QtQuick
import "../../../components"

// Small rounded text button of the Notification Center (iOS «Show Less» /
// «Clear All» / ✕ pills).
Rectangle {
    id: pill
    property string label
    // Island frost state: the pill surface fades with the frosted body.
    property var frost: null
    readonly property color base: pillMa.containsMouse ? "#3A3A3C" : "#2C2C2E"
    signal clicked

    width: Math.max(height, pillText.implicitWidth + 20)
    height: 26
    radius: 13
    color: pill.frost?.layerColor(pill.base) ?? pill.base

    Text {
        id: pillText
        anchors.centerIn: parent
        text: pill.label
        font.pixelSize: 12
        color: "#D5DAE2"
    }
    MouseArea {
        id: pillMa
        anchors.fill: parent
        hoverEnabled: true
        onClicked: pill.clicked()
    }
}
