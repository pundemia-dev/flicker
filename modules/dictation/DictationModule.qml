import QtQuick
import "../../components"

Item {
    id: root
    required property var dictation
    signal closeRequested

    property string lastTranscript: ""

    Connections {
        target: root.dictation
        function onTranscribed(text: string): void {
            root.lastTranscript = text;
        }
    }

    Row {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        Rectangle {
            width: 34
            height: 34
            radius: 17
            anchors.verticalCenter: parent.verticalCenter
            color: root.dictation.active ? "#C74E5A" : "#39414E"
            Text {
                anchors.centerIn: parent
                text: root.dictation.active ? "⏹" : "🎙"
                font.pixelSize: 13
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.dictation.toggle()
            }
        }

        Column {
            width: parent.width - 54
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Text {
                text: root.dictation.active ? "Listening..." : "Dictation ready"
                color: "#E5EAF3"
                font.pixelSize: 12
            }
            Text {
                width: parent.width
                text: root.lastTranscript
                color: "#98A4B6"
                font.pixelSize: 11
                elide: Text.ElideRight
                visible: root.lastTranscript.length > 0
            }
        }
    }
}
