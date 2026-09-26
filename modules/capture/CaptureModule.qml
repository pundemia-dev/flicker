import QtQuick
import Quickshell
import "../../components"

Item {
    id: root
    required property var compositor
    required property var recorder
    signal closeRequested

    readonly property var actions: [
        { label: "Shot", run: () => root.compositor.screenshot("") },
        { label: "Region", run: () => root.compositor.runRegionCapture("screenshot") },
        { label: root.recorder.recording ? "Stop" : "Record", run: () => root.recorder.recording ? root.recorder.stop() : root.compositor.startRecording("") },
        { label: "AI", run: () => root.compositor.runRegionCapture("ai") }
    ]

    Row {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        Repeater {
            model: root.actions

            Rectangle {
                required property var modelData
                width: (root.width - 20 - 3 * 8) / 4
                height: root.height - 20
                radius: 12
                color: ma.containsMouse ? "#2E3644" : "#242A34"

                Column {
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.label
                        color: "#E6EBF5"
                        font.pixelSize: 11
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 14
                        height: 3
                        radius: 1.5
                        color: modelData.label === "Stop" ? "#D94756" : "#5A7BB8"
                    }
                }

                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        modelData.run();
                        root.closeRequested();
                    }
                }
            }
        }
    }
}
