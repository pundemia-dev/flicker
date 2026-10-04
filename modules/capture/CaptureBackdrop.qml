import QtQuick

// Frozen screen (the grim grab, shown 1:1 over the live output) with an
// optional live HOLE over the island band: the island's own capture
// animation (content fade, steal, second instance sliding in) happens on
// the live surface underneath and must stay visible. The hole is cut by
// drawing the image in three clipped pieces (left, right, below) — no
// shaders, no layers. Until the image decodes nothing is drawn, which looks
// identical (the live screen is still the same frame).
Item {
    id: root
    property string source: ""
    // Local rect, top-anchored band; zero width = no hole.
    property rect hole: Qt.rect(0, 0, 0, 0)

    readonly property var pieces: root.hole.width <= 0 ? [Qt.rect(0, 0, root.width, root.height)] : [
        Qt.rect(0, 0, Math.max(0, root.hole.x), root.height),
        Qt.rect(root.hole.x + root.hole.width, 0, Math.max(0, root.width - root.hole.x - root.hole.width), root.height),
        Qt.rect(root.hole.x, root.hole.y + root.hole.height, root.hole.width, Math.max(0, root.height - root.hole.y - root.hole.height))
    ]

    Repeater {
        model: root.pieces

        Item {
            required property rect modelData
            x: modelData.x
            y: modelData.y
            width: modelData.width
            height: modelData.height
            clip: true

            Image {
                x: -parent.x
                y: -parent.y
                width: root.width
                height: root.height
                source: root.source
                asynchronous: true
                smooth: false
            }
        }
    }
}
