import QtQuick

Rectangle {
    id: root
    property bool active: false
    property int elapsedSeconds: 0
    signal activated

    width: active ? 54 : 0
    height: 22
    radius: 11
    color: "#D94756"
    visible: active

    Text {
        anchors.centerIn: parent
        color: "white"
        font.pixelSize: 11
        text: {
            const m = Math.floor(root.elapsedSeconds / 60).toString().padStart(2, "0");
            const s = (root.elapsedSeconds % 60).toString().padStart(2, "0");
            return `${m}:${s}`;
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.activated()
    }
}
