import QtQuick

// Soft inner shadow along a rounded rect's rim (no shader — KeyboardPill's
// stacked rings turned inward): inset 1 px outlines, darkest at the edge,
// fading out `size` px in. Nothing is filled, so a translucent surface
// under it keeps its colour in the middle. Size it like the surface it
// darkens (anchors.fill or explicit geometry), `radius` = its corner.
Item {
    id: root
    property real radius: 0
    property int size: 14
    // Alpha at the very edge (falls off quadratically inward).
    property real strength: 0.06

    Repeater {
        model: Math.max(0, Math.min(root.size, Math.floor(Math.min(root.width, root.height) / 2)))
        Rectangle {
            id: ring
            required property int index
            readonly property real t: ring.index / root.size
            x: ring.index
            y: ring.index
            width: root.width - 2 * ring.index
            height: root.height - 2 * ring.index
            radius: Math.max(0, root.radius - ring.index)
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, root.strength * (1 - ring.t) * (1 - ring.t))
        }
    }
}
