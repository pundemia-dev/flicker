import QtQuick
import "../../components"

// Tab rail right of the grid: one icon per page, top to bottom, centred
// vertically. Icons are picked by the module from each page's content
// (`glyphs`). A light disc marks the current page and follows the LIVE
// page position (mid-swipe it sits between icons). Edit mode adds a "+"
// (new tab) at the end; dragging a card over an icon flips to that page
// (indexAt()).
Item {
    id: root
    required property var cfg
    required property var theme
    property var frost: null
    required property var glyphs
    required property real pagePos
    property bool editing: false
    signal pageRequested(int index)
    signal addRequested

    readonly property real icon: root.cfg.railIcon
    readonly property real pitch: root.cfg.railIcon + root.cfg.railSpacing
    readonly property int count: root.glyphs.length + (root.editing ? 1 : 0)
    readonly property real columnH: root.count * root.icon + Math.max(0, root.count - 1) * root.cfg.railSpacing
    readonly property real colTop: (root.height - root.columnH) / 2

    // Page index under rail-local y; -2 = the "+", -1 = none.
    function indexAt(y: real): int {
        const i = Math.floor((y - root.colTop + root.cfg.railSpacing / 2) / root.pitch);
        if (i < 0 || i >= root.count)
            return -1;
        return i === root.glyphs.length ? -2 : i;
    }

    Rectangle {
        x: (root.width - width) / 2
        y: root.colTop + Math.max(0, Math.min(root.glyphs.length - 1, root.pagePos)) * root.pitch
        width: root.icon
        height: root.icon
        radius: width / 2
        color: root.frost?.layerColor(root.theme?.qsDisc ?? "#3A3A3C") ?? (root.theme?.qsDisc ?? "#3A3A3C")
        visible: root.glyphs.length > 0
    }

    Repeater {
        model: root.count
        delegate: Item {
            id: slot
            required property int index
            readonly property bool plus: index === root.glyphs.length
            readonly property real near: Math.max(0, 1 - Math.abs(root.pagePos - index))
            x: (root.width - width) / 2
            y: root.colTop + index * root.pitch
            width: root.icon
            height: root.icon

            Icon {
                anchors.centerIn: parent
                text: slot.plus ? "" : root.glyphs[slot.index]
                font.family: root.theme?.iconFamily ?? "tabler-icons"
                iconSize: Math.round(root.icon * 0.55)
                // Current page white, others dim; blends while swiping.
                iconColor: Qt.rgba(1, 1, 1, slot.plus ? 0.7 : 0.45 + 0.55 * slot.near)
            }
            MouseArea {
                anchors.fill: parent
                onClicked: slot.plus ? root.addRequested() : root.pageRequested(slot.index)
            }
        }
    }
}
