import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../../../components"

// Details of the selected app: big icon, name, description, command line.
Item {
    id: root
    required property var app
    required property var theme
    required property var cfg

    Column {
        anchors.centerIn: parent
        width: parent.width
        spacing: 8

        IconImage {
            anchors.horizontalCenter: parent.horizontalCenter
            implicitSize: root.cfg.apps.detailsIconSize
            asynchronous: true
            source: root.app ? Quickshell.iconPath(root.app.icon, "application-x-executable") : ""
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.app?.name ?? ""
            font.pixelSize: root.cfg.fontSize + 3
            font.weight: Font.DemiBold
            color: root.theme.islandFg
        }
        Text {
            width: parent.width
            visible: text !== ""
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            maximumLineCount: 4
            elide: Text.ElideRight
            text: root.app?.comment || root.app?.genericName || ""
            font.pixelSize: root.cfg.subFontSize
            color: root.theme.cardDim
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
            text: (root.app?.command ?? []).join(" ")
            font.family: "monospace"
            font.pixelSize: root.cfg.subFontSize - 1
            color: root.theme.cardDim
            opacity: 0.7
        }
    }
}
