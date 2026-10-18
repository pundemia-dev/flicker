import QtQuick
import "../../components"
import "../../config"

// Sidebar section row (iPadOS): coloured icon tile + title; the current
// section sits on an accent plate. In the rail only the tile shows and the
// plate shrinks to a square around it.
Item {
    id: root
    required property var theme
    required property var section
    property bool current: false
    property bool rail: false
    signal picked

    readonly property real tile: 30
    height: 44

    Rectangle {
        x: root.rail ? (root.width - width) / 2 : 0
        width: root.rail ? root.tile + 14 : root.width
        height: parent.height
        radius: 11
        color: root.current ? root.theme.qsBlue : area.containsMouse ? root.theme.settingsGroup : "transparent"
        Behavior on width { Spring { stiffness: 6; damp: 0.6 } }
    }

    IconTile {
        id: tile
        x: root.rail ? (root.width - width) / 2 : 7
        anchors.verticalCenter: parent.verticalCenter
        width: root.tile
        height: root.tile
        radius: root.tile * root.theme.iconTileRadius
        theme: root.theme
        Behavior on x { Spring { stiffness: 6; damp: 0.6 } }

        Text {
            anchors.centerIn: parent
            renderType: Text.CurveRendering
            text: root.section.glyph
            color: root.theme[root.section.tint] ?? root.theme.qsBlue
            font.family: root.theme.iconFamily
            font.pixelSize: 19
        }
    }

    Text {
        x: tile.x + tile.width + 12
        anchors.verticalCenter: parent.verticalCenter
        width: root.width - x - 8
        text: I18n.tr(root.section.title)
        elide: Text.ElideRight
        color: root.current ? "white" : root.theme.islandFg
        font.family: root.theme.fontFamily
        font.pixelSize: 15
        font.weight: root.current ? Font.DemiBold : Font.Normal
        opacity: root.rail ? 0 : 1
        Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.picked()
    }
}
