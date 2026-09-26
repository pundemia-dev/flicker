import QtQuick

Item {
    id: root
    property real value: 0
    property real min: 0
    property real max: 1
    signal valueChangedByUser(real value)

    implicitHeight: 20
    implicitWidth: 160

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4
        radius: 2
        color: "#3A3F48"
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, Math.min(parent.width, parent.width * ((root.value - root.min) / Math.max(0.0001, root.max - root.min))))
        height: 4
        radius: 2
        color: "#7EA9FF"
    }

    Rectangle {
        width: 12
        height: 12
        radius: 6
        color: "#F1F5FF"
        x: Math.max(0, Math.min(parent.width - width, parent.width * ((root.value - root.min) / Math.max(0.0001, root.max - root.min)) - width / 2))
        anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
        anchors.fill: parent
        onPressed: update(mouse.x)
        onPositionChanged: update(mouse.x)
        function update(xpos: real): void {
            const ratio = Math.max(0, Math.min(1, xpos / root.width));
            root.valueChangedByUser(root.min + (root.max - root.min) * ratio);
        }
    }
}
