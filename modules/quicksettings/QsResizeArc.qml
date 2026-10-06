import QtQuick
import QtQuick.Shapes

// Edit-mode resize grip of a QS card: a round-capped stroke bent TIGHTER than
// the card's bottom-right corner rounding (radius = radius * curve). Its
// middle sits ON the rounding circle at the 45° diagonal (centre line
// tangent there, half the thickness outside the card), the ends curl inward
// until their cap centres land on the circle of radius `endRadius` around the
// rounding centre (the inner edge of the edit rim) — that sets the length.
Shape {
    id: root
    // Rounding circle of the card corner (card coords) + its radius.
    property real cx: 0
    property real cy: 0
    property real radius: 40
    property real thickness: 12
    property real endRadius: 37
    property real curve: 0.45
    property color color: "white"

    preferredRendererType: Shape.CurveRenderer

    readonly property real r: root.radius * Math.max(0.05, Math.min(1, root.curve))
    // Own centre on the diagonal: the arc touches the rounding circle there.
    readonly property real shift: (root.radius - root.r) * Math.SQRT1_2
    // Half-angle at the own centre to a point at endRadius from the rounding
    // centre (law of cosines; d = R - r between the two centres).
    readonly property real ownSweep: {
        const d = root.radius - root.r;
        if (d < 0.001)
            return 90;
        const c = (root.endRadius * root.endRadius - d * d - root.r * root.r) / (2 * d * root.r);
        return 2 * Math.acos(Math.max(-1, Math.min(1, c))) * 180 / Math.PI;
    }

    ShapePath {
        fillColor: "transparent"
        strokeColor: root.color
        strokeWidth: root.thickness
        capStyle: ShapePath.RoundCap

        PathAngleArc {
            centerX: root.cx + root.shift
            centerY: root.cy + root.shift
            radiusX: root.r
            radiusY: root.r
            startAngle: 45 - root.ownSweep / 2
            sweepAngle: root.ownSweep
        }
    }
}
