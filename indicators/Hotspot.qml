import QtQuick

Rectangle {
    id: root
    property bool active: false
    signal activated

    width: active ? 24 : 0
    height: 20
    radius: 10
    color: "#3FBF73"
    visible: active

    Text {
        anchors.centerIn: parent
        text: "◉"
        color: "white"
        font.pixelSize: 11
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.activated()
    }
}
