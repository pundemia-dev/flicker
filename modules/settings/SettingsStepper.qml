import QtQuick
import "../../components"

// iOS stepper: one rounded pill split into − | +. Holding a half repeats
// (after a pause, then faster). An end that is reached greys out.
Rectangle {
    id: root
    required property var theme
    property bool canDown: true
    property bool canUp: true
    signal stepped(int dir)

    width: 94
    height: 32
    radius: 9
    color: root.theme.settingsPressed

    Rectangle {
        anchors.centerIn: parent
        width: 1
        height: parent.height - 14
        color: root.theme.settingsSecondary
        opacity: 0.4
    }

    Repeater {
        model: [-1, 1]

        Item {
            id: half
            required property int modelData
            readonly property bool can: half.modelData < 0 ? root.canDown : root.canUp
            x: half.modelData < 0 ? 0 : root.width / 2
            width: root.width / 2
            height: root.height

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: root.radius - 2
                color: root.theme.settingsGroup
                opacity: area.pressed && half.can ? 1 : 0
            }

            Text {
                anchors.centerIn: parent
                text: half.modelData < 0 ? "" : ""
                color: root.theme.islandFg
                opacity: half.can ? 1 : 0.3
                font.family: root.theme.iconFamily
                font.pixelSize: 18
            }

            MouseArea {
                id: area
                anchors.fill: parent
                cursorShape: half.can ? Qt.PointingHandCursor : Qt.ArrowCursor
                onPressed: {
                    if (!half.can)
                        return;
                    root.stepped(half.modelData);
                    repeat.interval = 400;
                    repeat.start();
                }
                onReleased: repeat.stop()
                onCanceled: repeat.stop()
            }

            Timer {
                id: repeat
                repeat: true
                onTriggered: {
                    if (!half.can)
                        return stop();
                    interval = 70;
                    root.stepped(half.modelData);
                }
            }
        }
    }
}
