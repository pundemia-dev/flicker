pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../../components"

// Menu of a system tray item (QsTray: right click / long press) as a QS
// panel — platform menus (QsMenuAnchor) need QApplication mode, which the
// shell does not run in. Header = the item's icon + title (a submenu: back
// button + the entry's text); rows = the DBus menu entries (check / radio
// state, icon, a chevron for a submenu, which opens in place). A tap on a
// plain entry triggers it and closes QS, like activating the item.
// payload = { item: SystemTrayItem, icon: resolved icon source }.
Item {
    id: root
    property var services: null
    property var cfg: null
    property var theme: null
    property var frost: null
    property var expander: null
    property var payload: null
    signal closeRequested

    readonly property var item: root.payload?.item ?? null
    readonly property var pc: root.cfg?.listPanel ?? ({})
    readonly property real pad: root.pc.padding ?? 18
    // Open submenus, outermost first.
    property var stack: []
    readonly property var current: root.stack.length > 0 ? root.stack[root.stack.length - 1] : (root.item?.menu ?? null)

    // "&File" → "File", "&&" → "&".
    function label(text: string): string {
        return (text ?? "").replace(/&(.)/g, "$1");
    }

    function choose(entry: var): void {
        if (!entry || !entry.enabled)
            return;
        if (entry.hasChildren) {
            root.stack = root.stack.concat([entry]);
            return;
        }
        entry.triggered();
        root.closeRequested();
    }

    QsMenuOpener {
        id: opener
        menu: root.current
    }

    Item {
        id: header
        width: parent.width
        height: (root.pc.headerHeight ?? 54) + 1

        PanelButton {
            id: back
            x: root.pad - 8
            anchors.verticalCenter: parent.verticalCenter
            visible: root.stack.length > 0
            pc: root.pc
            theme: root.theme
            frost: root.frost
            glyph: ""
            onClicked: root.stack = root.stack.slice(0, -1)
        }
        IconImage {
            id: appIcon
            x: back.visible ? back.x + back.width + 4 : root.pad
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: root.pc.glyphSize ?? 20
            source: root.payload?.icon ?? ""
            asynchronous: true
        }
        Text {
            x: appIcon.x + appIcon.width + 12
            width: parent.width - x - root.pad
            anchors.verticalCenter: parent.verticalCenter
            text: root.stack.length > 0
                ? root.label(root.current?.text ?? "")
                : (root.item?.tooltipTitle || root.item?.title || root.item?.id || "")
            color: "white"
            font.pixelSize: root.pc.titleSize ?? 17
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Rectangle {
            anchors.bottom: parent.bottom
            x: root.pad
            width: parent.width - 2 * root.pad
            height: 1
            color: root.theme?.launcherDivider ?? "#2EFFFFFF"
        }
    }

    ListView {
        id: list
        y: header.height + 4
        width: parent.width
        height: parent.height - y - 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: opener.children
        delegate: Item {
            id: row
            required property var modelData
            readonly property var entry: row.modelData
            readonly property bool checked: row.entry.buttonType !== QsMenuButtonType.None
                && row.entry.checkState === Qt.Checked
            width: list.width
            height: row.entry.isSeparator ? 9 : (root.pc.rowHeight ?? 42)
            opacity: row.entry.enabled || row.entry.isSeparator ? 1 : 0.4

            Rectangle {
                visible: row.entry.isSeparator
                anchors.verticalCenter: parent.verticalCenter
                x: root.pad
                width: parent.width - 2 * root.pad
                height: 1
                color: root.theme?.launcherDivider ?? "#2EFFFFFF"
            }

            Rectangle {
                visible: !row.entry.isSeparator
                x: 6
                width: parent.width - 12
                height: parent.height
                radius: height / 2
                color: root.frost?.layerColor(root.theme?.qsDisc ?? "#3A3A3C") ?? (root.theme?.qsDisc ?? "#3A3A3C")
                opacity: rowMa.pressed ? 0.8 : rowMa.containsMouse ? 0.45 : 0
                Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
            }

            // Left slot: check mark (checkbox / radio on), else the entry's icon.
            Item {
                id: lead
                visible: !row.entry.isSeparator
                x: root.pad
                width: root.pc.glyphSize ?? 20
                height: parent.height
                Icon {
                    anchors.centerIn: parent
                    visible: row.checked
                    text: ""
                    font.family: root.theme?.iconFamily ?? "tabler-icons"
                    iconSize: (root.pc.glyphSize ?? 20) - 2
                    iconColor: "white"
                }
                IconImage {
                    anchors.centerIn: parent
                    visible: !row.checked && (row.entry.icon ?? "") !== ""
                    implicitSize: (root.pc.glyphSize ?? 20) - 2
                    source: row.entry.icon ?? ""
                    asynchronous: true
                }
            }

            Text {
                visible: !row.entry.isSeparator
                x: lead.x + lead.width + 12
                width: (chevron.visible ? chevron.x - 8 : parent.width - root.pad) - x
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: root.label(row.entry.text)
                color: "white"
                font.pixelSize: root.pc.textSize ?? 14
                elide: Text.ElideRight
            }

            Icon {
                id: chevron
                visible: !row.entry.isSeparator && row.entry.hasChildren
                anchors.right: parent.right
                anchors.rightMargin: root.pad
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                font.family: root.theme?.iconFamily ?? "tabler-icons"
                iconSize: (root.pc.glyphSize ?? 20) - 4
                iconColor: root.theme?.cardDim ?? "#99EBEBF5"
            }

            MouseArea {
                id: rowMa
                anchors.fill: parent
                enabled: !row.entry.isSeparator && row.entry.enabled
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.choose(row.entry)
            }
        }
    }

    Text {
        anchors.centerIn: list
        visible: list.count === 0
        text: "…"
        color: root.theme?.cardDim ?? "#99EBEBF5"
        font.pixelSize: root.pc.textSize ?? 14
    }
}
