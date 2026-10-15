import QtQuick
import "../../../components"

// Header of an expanded QS card panel: the card's glyph on a disc (accent
// while on; tap = the card's toggle), title + status line, hairline below.
Item {
    id: root
    property var pc: ({})
    property var theme: null
    property var frost: null
    property real pad: 18
    property bool on: false
    property color accent: root.theme?.qsBlue ?? "#017EFC"
    property string glyph: ""
    property string title: ""
    property string status: ""
    signal toggled

    height: (root.pc.headerHeight ?? 54) + 1

    Rectangle {
        id: disc
        readonly property real d: Math.round((root.height - 1) * 0.67)
        x: root.pad
        y: Math.round((root.height - 1 - height) / 2)
        width: d
        height: d
        radius: d / 2
        color: discColor.value
        scale: discMa.pressed ? 0.9 : 1
        Behavior on scale { Spring { stiffness: 6; damp: 0.45; eps: 0.002 } }
        SpringColor {
            id: discColor
            target: root.on ? root.accent : (root.frost?.layerColor(root.theme?.qsDisc ?? "#3A3A3C") ?? (root.theme?.qsDisc ?? "#3A3A3C"))
            stiffness: 5
            damping: 0.6
        }
        Icon {
            anchors.centerIn: parent
            text: root.glyph
            font.family: root.theme?.iconFamily ?? "tabler-icons"
            iconSize: root.pc.glyphSize ?? 20
            iconColor: "white"
        }
        MouseArea {
            id: discMa
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggled()
        }
    }

    Column {
        x: disc.x + disc.width + 12
        width: root.width - x - root.pad
        y: Math.round((root.height - 1 - height) / 2)
        spacing: 1
        Text {
            width: parent.width
            text: root.title
            color: "white"
            font.pixelSize: root.pc.titleSize ?? 17
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            text: root.status
            color: root.theme?.cardDim ?? "#99EBEBF5"
            font.pixelSize: (root.pc.textSize ?? 14) - 2
            elide: Text.ElideRight
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        x: root.pad
        width: root.width - 2 * root.pad
        height: 1
        color: root.theme?.launcherDivider ?? "#2EFFFFFF"
    }
}
