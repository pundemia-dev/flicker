import QtQuick
import "../../components"
import "../../config"

// One LocalSend peer row (pShell DeviceUnit port): type glyph, alias and two
// badges (#last IP octet, advertised device model). Roles from
// LocalSend.devices: name / ip / kind / os.
Rectangle {
    id: root
    required property string name
    required property string ip
    required property string kind
    required property string os
    required property var theme
    signal picked(string ip)

    readonly property string typeGlyph: {
        switch (root.kind.toLowerCase()) {
        case "mobile":
            return "";
        case "laptop":
            return "";
        case "desktop":
            return "";
        case "tablet":
            return "";
        default:
            return "";
        }
    }
    readonly property string ipBadge: {
        const m = root.ip.match(/(\d+)$/);
        return m ? "#" + m[1] : "";
    }

    property real hot: ma.containsMouse ? 1 : 0
    Behavior on hot { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
    color: Qt.tint(root.theme.cardBg, Qt.alpha(root.theme.cardBlue, 0.18 * root.hot))

    Text {
        id: glyph
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: root.typeGlyph
        color: root.theme.cardBlue
        font.family: root.theme.iconFamily
        font.pixelSize: 24
    }

    Column {
        anchors.left: glyph.right
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        Text {
            width: parent.width
            text: root.name
            color: root.theme.islandFg
            font.pixelSize: root.theme.fontSizeClock
            elide: Text.ElideRight
        }
        Row {
            spacing: 4
            Badge {
                visible: root.ipBadge !== ""
                label: root.ipBadge
                tint: root.theme.cardBlue
            }
            Badge {
                label: root.os.trim() !== "" ? root.os : I18n.tr("Unknown")
                tint: root.theme.subtleFg
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.picked(root.ip)
    }

    component Badge: Rectangle {
        property string label
        property color tint
        radius: 4
        color: Qt.alpha(tint, 0.18)
        implicitWidth: badgeText.implicitWidth + 8
        implicitHeight: badgeText.implicitHeight + 2
        Text {
            id: badgeText
            anchors.centerIn: parent
            text: parent.label
            color: parent.tint
            font.pixelSize: root.theme.fontSizeTiny
        }
    }
}
