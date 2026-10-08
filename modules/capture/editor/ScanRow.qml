import QtQuick
import "../../../components"
import "../../../config"

// One decoded code in the ScanPanel: type + data (3 lines max); a click on
// the row copies it, links get an "open" button.
Rectangle {
    id: root
    required property var panel
    required property var entry
    readonly property bool hovered: hover.containsMouse
    signal copy
    signal openLink

    readonly property var theme: root.panel.theme
    readonly property var cfg: root.panel.cfg
    readonly property bool link: root.panel.isLink(root.entry.data)

    height: Math.max(body.implicitHeight, root.cfg.toolButtonSize) + root.cfg.panelPad
    radius: root.cfg.toolRadius
    color: root.hovered ? root.theme.cardTrack : root.theme.cardBg

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.copy()
    }

    Column {
        id: body
        anchors.left: parent.left
        anchors.right: openBtn.visible ? openBtn.left : parent.right
        anchors.margins: root.cfg.panelPad / 2
        anchors.verticalCenter: parent.verticalCenter

        Text {
            text: root.entry.type
            color: root.theme.subtleFg
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fontSizeTiny
        }
        Text {
            width: parent.width
            text: root.entry.data
            color: root.link ? root.theme.cardBlue : root.theme.islandFg
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 3
            elide: Text.ElideRight
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fontSizeBody
        }
    }

    IconButton {
        id: openBtn
        theme: root.theme
        visible: root.link
        anchors.right: parent.right
        anchors.rightMargin: root.cfg.panelPad / 2
        anchors.verticalCenter: parent.verticalCenter
        width: root.cfg.toolButtonSize
        height: width
        bg: root.theme.islandBg
        glyph: ""
        iconSize: root.cfg.toolIconSize
        onClicked: root.openLink()
    }
}
