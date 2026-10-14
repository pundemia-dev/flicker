import QtQuick
import QtQuick.Shapes
import "MorphShape.js" as MorphShape

// A filled outline morphing between two MorphShape kinds (`from` → `to` at
// `t` 0..1), the M3 expressive MaterialShape look in pure QML. CurveRenderer
// keeps the edge antialiased at small sizes.
Shape {
    id: root

    property string from: "circle"
    property string to: "circle"
    property real t: 0
    property color color: "white"
    property real turn: 0
    property int segments: 72

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillColor: root.color

        PathPolyline {
            path: MorphShape.points(root.from, root.to, Math.max(0, Math.min(1, root.t)), Math.min(root.width, root.height), root.segments, root.turn)
        }
    }
}
