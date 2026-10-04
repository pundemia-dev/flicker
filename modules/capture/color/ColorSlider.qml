import QtQuick

// Gradient channel slider for the colour panel (port of pShell's
// ColorSlider): rounded track previewing the channel sweep + a narrow bar
// handle with a background gap carved around it; the bar grows while held.
Item {
    id: root
    required property var theme
    property real value: 0
    property var colorAt: t => "#000000"
    property real barW: 4
    property int growMs: 90
    signal moved(real v)
    signal finished

    readonly property real knobX: root.value * (root.width - root.barW)

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: root.colorAt(0) }
            GradientStop { position: 1 / 6; color: root.colorAt(1 / 6) }
            GradientStop { position: 2 / 6; color: root.colorAt(2 / 6) }
            GradientStop { position: 0.5; color: root.colorAt(0.5) }
            GradientStop { position: 4 / 6; color: root.colorAt(4 / 6) }
            GradientStop { position: 5 / 6; color: root.colorAt(5 / 6) }
            GradientStop { position: 1; color: root.colorAt(1) }
        }
    }

    Rectangle {
        x: root.knobX - root.barW
        width: root.barW * 3
        height: parent.height
        color: root.theme.islandBg
    }

    Rectangle {
        x: root.knobX
        anchors.verticalCenter: parent.verticalCenter
        width: root.barW
        height: root.height + (sliderMa.pressed ? root.barW * 2 : root.barW)
        radius: width / 2
        color: root.theme.islandFg
        Behavior on height { NumberAnimation { duration: root.growMs } }
    }

    MouseArea {
        id: sliderMa
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        function apply(mx: real): void {
            root.moved(Math.max(0, Math.min(1, (mx - root.barW / 2) / (root.width - root.barW))));
        }
        onPressed: mouse => apply(mouse.x)
        onPositionChanged: mouse => apply(mouse.x)
        onReleased: root.finished()
    }
}
