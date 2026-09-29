import QtQuick

// Thin progress bar (battery level, per-process CPU). Value is 0..1.
Rectangle {
    id: root
    required property var theme
    property real value: 0
    property color fill: "#30D158"

    height: 6
    radius: 3
    color: theme?.cardTrack ?? "#2C2C2E"

    Rectangle {
        width: root.width * Math.max(0, Math.min(1, root.value))
        height: root.height
        radius: root.radius
        color: root.fill
    }
}
