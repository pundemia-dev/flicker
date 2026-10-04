import QtQuick
import "../../../components"

// Small rounded text button of the Notification Center (iOS «Свернуть» /
// «Очистить» / ✕ pills).
Rectangle {
    id: pill
    property string label
    signal clicked

    width: Math.max(height, pillText.implicitWidth + 20)
    height: 26
    radius: 13
    color: pillMa.containsMouse ? "#3A3A3C" : "#2C2C2E"

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
