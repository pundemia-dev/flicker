import QtQuick

Item {
    property real value: 0
    implicitHeight: 5
    implicitWidth: 130

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: "#3A3F48"
    }
    Rectangle {
        width: parent.width * Math.max(0, Math.min(1, value))
        height: parent.height
        radius: height / 2
        color: "#79B5FF"
    }
}
