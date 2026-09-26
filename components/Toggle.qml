import QtQuick

Rectangle {
    id: root
    property bool checked: false
    signal toggled(bool checked)

    width: 38
    height: 22
    radius: 11
    color: checked ? "#5DA8FF" : "#545C69"

    Rectangle {
        width: 18
        height: 18
        radius: 9
        y: 2
        x: checked ? root.width - width - 2 : 2
        color: "white"
        Behavior on x {
            Spring {}
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            root.checked = !root.checked;
            root.toggled(root.checked);
        }
    }
}
