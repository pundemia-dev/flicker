import QtQuick
import "../../components"

// Frozen screen (the grim grab, shown 1:1 over the live output) with an
// optional live HOLE over the island band: the island's own capture
// animation (content fade, steal, second instance sliding in) happens on
// the live surface underneath and must stay visible. The hole is cut by
// drawing the image in three clipped pieces (left, right, below) — no
// shaders, no layers. Until the image decodes nothing is drawn, which looks
// identical (the live screen is still the same frame).
// Once the island background has flown off into the cursor square the
// island idles as a Minimal strip, so the hole is FILLED with the frozen
// frame (`holeFilled`, fades in): the preview shows the bar exactly as the
// screenshot will. On close it fades out over the bar re-expanding live.
Item {
    id: root
    property string source: ""
    // Local rect, top-anchored band; zero width = no hole.
    property rect hole: Qt.rect(0, 0, 0, 0)
    property bool holeFilled: false

    readonly property var pieces: root.hole.width <= 0 ? [Qt.rect(0, 0, root.width, root.height)] : [
        Qt.rect(0, 0, Math.max(0, root.hole.x), root.height),
        Qt.rect(root.hole.x + root.hole.width, 0, Math.max(0, root.width - root.hole.x - root.hole.width), root.height),
        Qt.rect(root.hole.x, root.hole.y + root.hole.height, root.hole.width, Math.max(0, root.height - root.hole.y - root.hole.height))
    ]

    component Piece: Item {
        id: piece
        clip: true

        Image {
            x: -piece.x
            y: -piece.y
            width: root.width
            height: root.height
            source: root.source
            asynchronous: true
            smooth: false
        }
    }

    Piece {
        x: root.hole.x
        y: root.hole.y
        width: root.hole.width
        height: root.hole.height
        visible: root.hole.width > 0 && opacity > 0.001
        opacity: root.holeFilled ? 1 : 0
        Behavior on opacity { Spring { eps: 0.005 } }
    }

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
