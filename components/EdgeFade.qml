import QtQuick

// Fades content out towards all four edges by painting `color` gradients
// over them (`width` px each side, `strength` 0..1 as opacity). Meant for
// content sitting on an opaque `color` background (the true-black island):
// there, blending to the background colour IS fading to transparent.
// Purely visual, never takes input. Hidden (no nodes) at strength 0.
Item {
    id: root
    property color color: "black"
    property real edgeWidth: 24
    property real strength: 0
    readonly property real w: Math.min(root.edgeWidth, root.width / 2, root.height / 2)

    visible: root.strength > 0.001 && root.w > 0.5
    opacity: Math.max(0, Math.min(1, root.strength))

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.w
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: root.color }
            GradientStop { position: 1; color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0) }
        }
    }
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.w
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0) }
            GradientStop { position: 1; color: root.color }
        }
    }
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.w
        gradient: Gradient {
            GradientStop { position: 0; color: root.color }
            GradientStop { position: 1; color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0) }
        }
    }
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.w
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0) }
            GradientStop { position: 1; color: root.color }
        }
    }
}
