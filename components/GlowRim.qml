import QtQuick

// Soft light glow around a rounded shape (the island halo treatment):
// `rings` nested border rings just OUTSIDE the parent, alpha falling
// smoothly with distance — a faint haze, not an edge (keep peakAlpha tiny). Makes dark
// buttons readable on dark content. Fully declarative, follows the parent.
Item {
    id: root
    // Corner radius of the shape it surrounds.
    property real radius: 0
    property color color: "white"
    // Total spread outside the shape, px, and the innermost ring's alpha.
    property real spread: 3
    property real peakAlpha: 0.2
    property int rings: 3

    anchors.fill: parent

    Repeater {
        model: root.rings

        Rectangle {
            required property int index
            readonly property real step: root.spread / root.rings
            readonly property real off: step * (index + 1)
            x: -off
            y: -off
            width: root.width + off * 2
            height: root.height + off * 2
            radius: root.radius + off
            color: "transparent"
            border.width: step
            border.color: Qt.rgba(root.color.r, root.color.g, root.color.b,
                root.peakAlpha * Math.pow(1 - index / root.rings, 2))
        }
    }
}
