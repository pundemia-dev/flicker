import QtQuick
import QtQuick.Shapes

// One filled glyph shape: an SVG path with a vertical gradient (`colorTop` ->
// `colorBottom` over gy1..gy2; NOT top/bottom: FINAL Item members) and an optional glossy sheen — white at the top
// fading out halfway (the wallpaper-settings tile rim idea, as a fill).
// Overlapping parts of one glyph are separate GlyphFills with the same
// gradient span (CurveRenderer does not union overlapping subpaths).
Shape {
    id: f
    property string path: ""
    property color colorTop: "#FFFFFF"
    property color colorBottom: "#999999"
    property real gy1: 0
    property real gy2: f.height
    property bool oddEven: false
    property real sheen: 0

    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillRule: f.oddEven ? ShapePath.OddEvenFill : ShapePath.WindingFill
        fillGradient: LinearGradient {
            x1: 0; y1: f.gy1
            x2: 0; y2: f.gy2
            GradientStop { position: 0; color: f.colorTop }
            GradientStop { position: 1; color: f.colorBottom }
        }
        PathSvg { path: f.path }
    }
    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillRule: f.oddEven ? ShapePath.OddEvenFill : ShapePath.WindingFill
        fillGradient: LinearGradient {
            x1: 0; y1: f.gy1
            x2: 0; y2: f.gy1 + (f.gy2 - f.gy1) * 0.5
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, f.sheen) }
            GradientStop { position: 1; color: "transparent" }
        }
        PathSvg { path: f.sheen > 0 ? f.path : "" }
    }
}
