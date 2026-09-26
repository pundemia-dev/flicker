import QtQuick
import "../../components"

Item {
    id: root
    required property var payload
    signal closeRequested

    Row {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10
        Text {
            text: root.payload?.icon ?? "♪"
            color: "#F2F6FF"
            font.pixelSize: 16
            anchors.verticalCenter: parent.verticalCenter
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 38
            spacing: 4
            Text { text: root.payload?.title ?? "OSD"; color: "#DFE6F2"; font.pixelSize: 11 }
            ProgressBar { value: root.payload?.value ?? 0 }
        }
    }
}
