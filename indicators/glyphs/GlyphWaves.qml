import QtQuick
import QtQuick.Shapes

// Sound / signal arcs radiating from (cx, cy) toward `angle` (degrees,
// clockwise from 3 o'clock): `count` arcs travel from r0 to r0 + spread
// over `period`, each fading in and out (sin), staggered evenly. A timed
// infinite loop (a looping wave has no spring target — same exception as
// the ghost hem); `running` fades the whole set in / out.
Item {
    id: w
    property real cx: 0
    property real cy: 0
    property real r0: 4
    property real spread: 3
    property real angle: 0
    property real halfSpan: 38
    property int count: 2
    property int period: 1400
    property color color: "#FFFFFF"
    property real lineWidth: 1.4
    property bool running: false

    property real phase: 0
    property real show: w.running ? 1 : 0
    Behavior on show { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
    NumberAnimation on phase {
        running: w.show > 0
        from: 0
        to: 1
        duration: w.period
        loops: Animation.Infinite
    }

    anchors.fill: parent

    Repeater {
        model: w.count
        delegate: Shape {
            id: arc
            required property int index
            readonly property real t: (w.phase + arc.index / w.count) % 1
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            opacity: Math.sin(Math.PI * arc.t) * w.show
            ShapePath {
                fillColor: "transparent"
                strokeColor: w.color
                strokeWidth: w.lineWidth
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: w.cx
                    centerY: w.cy
                    radiusX: w.r0 + w.spread * arc.t
                    radiusY: w.r0 + w.spread * arc.t
                    startAngle: w.angle - w.halfSpan
                    sweepAngle: 2 * w.halfSpan
                }
            }
        }
    }
}
