import QtQuick
import "../../components"
import "../../config"

// One page: iOS large title that scrolls away under a compact header (the
// title shrinks into it, plus "‹ Back" on drill-down pages), then the
// grouped sections in a centred column. `slot` places it in the stack:
// 0 = on top, 1 = off to the right, -1 = under the top page (drifted left,
// dimmed); x follows on a spring.
Item {
    id: root
    required property var host
    required property var theme
    property var page: ({ title: "", groups: [] })
    property int depth: 0
    property string backLabel: ""
    property string emptyText: ""
    property real slot: 0
    property bool dying: false

    readonly property real pad: 20
    readonly property real headerHeight: 52
    readonly property real columnWidth: Math.min(root.width - 2 * root.pad, 680)
    // Compact header shows once the large title has scrolled under it.
    readonly property bool collapsed: flick.contentY > content.y + largeTitle.y + largeTitle.height - root.headerHeight

    x: root.slot > 0 ? root.slot * root.width : root.slot * root.width * 0.3
    Behavior on x { Spring { stiffness: 5; damp: 0.55; eps: 0.5 } }
    onXChanged: if (root.dying && root.x > root.width * 0.98) root.destroy()
    enabled: root.slot === 0 && !root.dying

    Rectangle {
        anchors.fill: parent
        color: root.theme.settingsCard
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.height + root.pad * 2
        boundsBehavior: Flickable.DragOverBounds

        Column {
            id: content
            x: Math.round((root.width - root.columnWidth) / 2)
            y: root.headerHeight
            width: root.columnWidth
            spacing: 24

            Text {
                id: largeTitle
                text: I18n.tr(root.page.title)
                color: root.theme.islandFg
                font.family: root.theme.fontFamily
                font.pixelSize: 30
                font.weight: Font.Bold
                bottomPadding: -10
            }

            Repeater {
                model: root.page.groups

                SettingsGroup {
                    required property var modelData
                    width: content.width
                    host: root.host
                    theme: root.theme
                    group: modelData
                }
            }

            Text {
                visible: root.page.groups.length === 0 && root.emptyText !== ""
                width: content.width
                topPadding: 40
                horizontalAlignment: Text.AlignHCenter
                text: root.emptyText
                color: root.theme.settingsSecondary
                font.family: root.theme.fontFamily
                font.pixelSize: 15
            }
        }
    }

    // Compact header: card-coloured bar + hairline once collapsed.
    Item {
        width: parent.width
        height: root.headerHeight

        Rectangle {
            anchors.fill: parent
            color: root.theme.settingsCard
            opacity: root.collapsed ? 1 : 0
            Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: root.theme.settingsSeparator
            }
        }

        Text {
            anchors.centerIn: parent
            text: I18n.tr(root.page.title)
            color: root.theme.islandFg
            font.family: root.theme.fontFamily
            font.pixelSize: 15
            font.weight: Font.DemiBold
            opacity: root.collapsed ? 1 : 0
            Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
        }

        // "‹ Parent" back button.
        Row {
            id: back
            visible: root.depth > 0
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            opacity: backArea.pressed ? 0.5 : 1

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                color: root.theme.qsBlue
                font.family: root.theme.iconFamily
                font.pixelSize: 20
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr(root.backLabel)
                color: root.theme.qsBlue
                font.family: root.theme.fontFamily
                font.pixelSize: 15
            }
        }

        MouseArea {
            id: backArea
            visible: back.visible
            x: back.x - 8
            y: back.y - 8
            width: back.width + 16
            height: back.height + 16
            cursorShape: Qt.PointingHandCursor
            onClicked: root.host.back()
        }
    }

    // Dim while another page sits on top.
    Rectangle {
        anchors.fill: parent
        color: root.theme.settingsMenuShade
        opacity: root.slot < 0 ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { Spring { stiffness: 5; damp: 0.6; eps: 0.01 } }
    }
}
