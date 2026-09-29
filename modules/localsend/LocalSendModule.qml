import QtQuick
import "../../components"

Item {
    id: root
    signal closeRequested

    Rectangle {
        anchors.fill: parent
        // No radius: the island clips content to its own corners, so a square
        // fill always matches (a smaller radius would leave double corners).
        color: "#1E232B"
        border.color: "#3A4554"
        Text {
            anchors.centerIn: parent
            text: "Drop zone for LocalSend"
            color: "#D4DCEA"
            font.pixelSize: 12
        }
    }
}
