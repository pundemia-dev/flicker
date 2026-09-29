import QtQuick
import QtQuick.Shapes
import "../../../components"

// Circular progress ring (CPU / RAM / disk). Concentric instances share one
// Item box with different ringRadius values (see SystemLoadCard).
// Fill glides via a calm spring (shared Spring.qml, retuned: near-critical
// damping so the gauge doesn't overshoot, epsilon 0.001 so it lands exact).
Item {
    id: root
    property real value: 0 // 0..1
    property color ringColor: "#FF453A"
    property color trackColor: "#2C2C2E"
    property real ringWidth: 8
    property real ringRadius: 38

    Behavior on value {
        Spring {
            damp: 0.7
            eps: 0.001
        }
    }

    readonly property real _frac: Math.max(0, Math.min(1, root.value))

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.trackColor
            strokeWidth: root.ringWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.ringRadius
                radiusY: root.ringRadius
                startAngle: -90
                sweepAngle: 359.9
            }
        }
        ShapePath {
            strokeColor: root.ringColor
            strokeWidth: root.ringWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.ringRadius
                radiusY: root.ringRadius
                startAngle: -90
                sweepAngle: 359.9 * root._frac
            }
        }
    }
}
