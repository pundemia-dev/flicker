import QtQuick

// Screen dim with an optional clear cut-out (selection / hovered window):
// four bands around `cut` (null = the whole screen dims).
Item {
    id: root
    property var cut: null
    property color color: "black"

    readonly property real cx: root.cut ? root.cut.x : 0
    readonly property real cy: root.cut ? root.cut.y : 0
    readonly property real cw: root.cut ? root.cut.width : 0
    readonly property real ch: root.cut ? root.cut.height : 0

    Rectangle {
        color: root.color
        width: root.width
        height: Math.max(0, root.cy)
    }
    Rectangle {
        color: root.color
        y: root.cy + root.ch
        width: root.width
        height: Math.max(0, root.height - y)
    }
    Rectangle {
        color: root.color
        y: root.cy
        width: Math.max(0, root.cx)
        height: root.ch
    }
    Rectangle {
        color: root.color
        x: root.cx + root.cw
        y: root.cy
        width: Math.max(0, root.width - x)
        height: root.ch
    }
}
