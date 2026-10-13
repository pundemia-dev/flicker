import QtQuick
import QtQuick.Shapes

// Light rim on a rounded card / icon tile (wallpaper settings, capture buttons): a thin white edge
// along the TOP, running all the way round both top corners (down to where
// the sides start), and along the BOTTOM, running only half way round the
// bottom corners (to 45°). Each is a filled sliver between the card outline
// and the outline inset by `rimWidth`, with a vertical gradient that fades
// it out along the corner arcs — no hard stroke ends. Stroke gradients do
// not exist in Shape, hence filled slivers (CurveRenderer: antialiased).
Item {
    id: root
    property real radius: 16
    // Own top-left corner (the capture cursor bubble's tip); default = radius.
    property real topLeftRadius: root.radius
    property real rimWidth: 1
    property color topColor: "#2EFFFFFF"
    property color bottomColor: "#14FFFFFF"

    readonly property real r: Math.min(root.radius, root.width / 2, root.height / 2)
    readonly property real w: root.rimWidth
    readonly property real ri: Math.max(0, root.r - root.w)
    readonly property real rl: Math.min(root.topLeftRadius, root.width / 2, root.height / 2)
    readonly property real ril: Math.max(0, root.rl - root.w)
    readonly property real k: Math.SQRT1_2 // cos/sin 45°

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        // Top: (0, rl) ↷ (rl, 0) — (W−r, 0) ↷ (W, r), back along the inner edge.
        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillGradient: LinearGradient {
                x1: 0; y1: 0
                x2: 0; y2: Math.max(root.r, root.rl)
                GradientStop { position: 0; color: root.topColor }
                GradientStop { position: 0.45; color: Qt.alpha(root.topColor, root.topColor.a * 0.55) }
                GradientStop { position: 1; color: "transparent" }
            }
            startX: 0
            startY: root.rl
            PathArc { x: root.rl; y: 0; radiusX: root.rl; radiusY: root.rl }
            PathLine { x: root.width - root.r; y: 0 }
            PathArc { x: root.width; y: root.r; radiusX: root.r; radiusY: root.r }
            PathLine { x: root.width - root.w; y: root.r }
            PathArc {
                x: root.width - root.r; y: root.w
                radiusX: root.ri; radiusY: root.ri
                direction: PathArc.Counterclockwise
            }
            PathLine { x: root.rl; y: root.w }
            PathArc {
                x: root.w; y: root.rl
                radiusX: root.ril; radiusY: root.ril
                direction: PathArc.Counterclockwise
            }
            PathLine { x: 0; y: root.rl }
        }

        // Bottom: from 45° on the bottom-left arc ↶ (r, H) — (W−r, H) ↶ 45° on
        // the bottom-right arc, back along the inner edge.
        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillGradient: LinearGradient {
                x1: 0; y1: root.height
                x2: 0; y2: root.height - root.r * (1 - root.k)
                GradientStop { position: 0; color: root.bottomColor }
                GradientStop { position: 1; color: "transparent" }
            }
            startX: root.r - root.r * root.k
            startY: root.height - root.r + root.r * root.k
            PathArc {
                x: root.r; y: root.height
                radiusX: root.r; radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathLine { x: root.width - root.r; y: root.height }
            PathArc {
                x: root.width - root.r + root.r * root.k; y: root.height - root.r + root.r * root.k
                radiusX: root.r; radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.width - root.r + root.ri * root.k
                y: root.height - root.r + root.ri * root.k
            }
            PathArc {
                x: root.width - root.r; y: root.height - root.w
                radiusX: root.ri; radiusY: root.ri
            }
            PathLine { x: root.r; y: root.height - root.w }
            PathArc {
                x: root.r - root.ri * root.k; y: root.height - root.r + root.ri * root.k
                radiusX: root.ri; radiusY: root.ri
            }
            PathLine { x: root.r - root.r * root.k; y: root.height - root.r + root.r * root.k }
        }
    }
}
