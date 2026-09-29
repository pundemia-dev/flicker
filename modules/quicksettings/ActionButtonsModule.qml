import QtQuick
import "../../components"

Item {
    id: root
    required property string kind
    required property var recorder
    required property var network
    required property var theme
    signal closeRequested

    Row {
        anchors.centerIn: parent
        spacing: 10

        Rectangle {
            width: 84
            height: 30
            radius: 10
            color: root.theme.islandBg
            Text { anchors.centerIn: parent; text: "Cancel"; color: root.theme.islandFg }
            MouseArea {
                anchors.fill: parent
                onClicked: root.closeRequested()
            }
        }
        Rectangle {
            width: 84
            height: 30
            radius: 10
            color: root.kind === "recording" ? root.theme.accentRed : root.theme.accentGreen
            Text { anchors.centerIn: parent; text: "Stop"; color: root.theme.islandFg }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (root.kind === "recording")
                        root.recorder.stop();
                    else
                        root.network.setHotspotEnabled(false);
                    root.closeRequested();
                }
            }
        }
    }
}
