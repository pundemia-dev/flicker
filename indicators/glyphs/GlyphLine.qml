import QtQuick
import QtQuick.Shapes

// One stroked glyph line (round caps / joins): reveal lines, runes,
// shackles, check marks.
Shape {
    id: l
    property string path: ""
    property color color: "#FFFFFF"
    property real lineWidth: 1.5

    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        fillColor: "transparent"
        strokeColor: l.color
        strokeWidth: l.lineWidth
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: l.path }
    }
}
