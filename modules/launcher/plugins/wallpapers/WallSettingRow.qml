import QtQuick
import "../../../../components"
import "../../../../config"

// One row of the wallpaper settings panel: label left, value right —
// bool = a small switch on the accent, choice = ‹ value ›, reset = red
// label only. A dot before the label marks a value changed from
// config.json. A click = `activated` (the panel steps the value).
Item {
    id: root
    required property var row
    required property var theme
    required property var c
    required property var lc
    property var value: null
    property string valueText: ""
    property bool changed: false
    signal activated

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: -width - 3
        width: 5
        height: 5
        radius: 2.5
        color: root.theme.qsBlue
        opacity: root.changed ? 1 : 0
        Behavior on opacity { Spring { eps: 0.01 } }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: valueBox.left
        anchors.rightMargin: 8
        text: I18n.tr(root.row.label)
        elide: Text.ElideRight
        color: root.row.kind === "reset" ? root.theme.accentRed : root.theme.islandFg
        font.family: root.theme.fontFamily
        font.pixelSize: root.lc.subFontSize
    }

    Item {
        id: valueBox
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.row.kind === "bool" ? sw.width : (root.row.kind === "choice" ? choice.implicitWidth : 0)
        height: parent.height

        Rectangle {
            id: sw
            visible: root.row.kind === "bool"
            readonly property bool on: !!root.value
            anchors.verticalCenter: parent.verticalCenter
            width: (root.c.settingsSwitchHeight ?? 20) * 1.75
            height: root.c.settingsSwitchHeight ?? 20
            radius: height / 2
            color: swColor.value
            SpringColor {
                id: swColor
                target: sw.on ? root.theme.qsBlue : root.theme.cardTrack
                stiffness: 5
                damping: 0.6
            }
            Rectangle {
                width: parent.height - 4
                height: width
                radius: width / 2
                y: 2
                x: sw.on ? parent.width - width - 2 : 2
                color: root.theme.islandFg
                Behavior on x { Spring {} }
            }
        }
        Text {
            id: choice
            visible: root.row.kind === "choice"
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            text: "‹  " + root.valueText + "  ›"
            color: root.theme.subtleFg
            font.family: root.theme.fontFamily
            font.pixelSize: root.lc.subFontSize
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
