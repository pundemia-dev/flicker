import QtQuick
import QtQuick.Shapes

// Clips arbitrary children to an antialiased rounded rectangle (same trick
// as RoundedImage: a layered wrapper is the texture of a CurveRenderer
// Shape via ShapePath.fillItem). Item clip is square-only and MultiEffect
// masks are a hard alpha threshold here (stair-stepped corners).
Item {
    id: root
    property real radius: 0
    default property alias content: inner.data

    Item {
        id: inner
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillColor: "white"
            fillItem: inner

            PathRectangle {
                x: 0
                y: 0
                width: root.width
                height: root.height
                radius: Math.min(root.radius, root.width / 2, root.height / 2)
            }
        }
    }
}
