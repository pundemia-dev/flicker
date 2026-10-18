import QtQuick
import "../../components"

// iOS slider: thin track, accent fill, round white knob. Press anywhere
// on it or drag; `moved` reports the raw value snapped to `step`.
Item {
    id: root
    required property var theme
    property real value: 0
    property real min: 0
    property real max: 1
    property real step: 0
    signal moved(real value)

    readonly property real knob: 26
    readonly property real frac: Math.max(0, Math.min(1, (root.value - root.min) / Math.max(1e-9, root.max - root.min)))
    implicitHeight: root.knob + 4

    Rectangle {
        id: track
        x: root.knob / 2
        width: root.width - root.knob
        anchors.verticalCenter: parent.verticalCenter
        height: 4
        radius: 2
        color: root.theme.settingsPressed

        Rectangle {
            width: track.width * root.frac
            height: parent.height
            radius: parent.radius
            color: root.theme.qsBlue
        }
    }

    Rectangle {
        x: track.width * root.frac
        anchors.verticalCenter: parent.verticalCenter
        width: root.knob
        height: root.knob
        radius: width / 2
        color: root.theme.islandFg
        scale: area.pressed ? 1.08 : 1
        Behavior on scale { Spring { stiffness: 6; damp: 0.5; eps: 0.005 } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        onPressed: mouse => update(mouse.x)
        onPositionChanged: mouse => update(mouse.x)

        function update(px: real): void {
            const f = Math.max(0, Math.min(1, (px - track.x) / track.width));
            let v = root.min + f * (root.max - root.min);
            if (root.step > 0)
                v = root.min + Math.round((v - root.min) / root.step) * root.step;
            v = Number(v.toFixed(6));
            if (v !== root.value)
                root.moved(v);
        }
    }
}
