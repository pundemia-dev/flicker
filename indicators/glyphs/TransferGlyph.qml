import QtQuick
import QtQuick.Shapes
import "../../components"
import "Glyph.js" as G

// File transfer (LocalSend): a progress ring draws itself closed, a
// download arrow drops into it. Loop: the arrow keeps flowing down (slides
// out at the bottom, re-enters from the top) while the ring shows the
// progress — `args.progress` (0..1, live) when the sender knows it, else
// an indeterminate arc spinning round.
GlyphBase {
    id: g
    glyphName: "transfer"

    property real ring: 0
    property real arrow: 0
    property real flow: 0
    property real spin: 0
    property bool looping: false
    readonly property var progress: g.args?.progress ?? null

    onBegin: ringAnim.start()
    onRingChanged: if (!arrowAnim.running && g.arrow === 0 && g.ring >= g.p("arrowAt", 0.5)) arrowAnim.start()
    onArrowChanged: if (!g.looping && g.arrow >= 1 - g.handoff) g.looping = true
    Spring { id: ringAnim; target: g; property: "ring"; to: 1; stiffness: g.p("revealStiffness", 6); damp: 1; eps: 0.002 }
    Spring { id: arrowAnim; target: g; property: "arrow"; to: 1; stiffness: g.p("popStiffness", 7); damp: g.p("popDamping", 0.45); eps: 0.002 }
    NumberAnimation on spin {
        running: g.looping && g.progress === null
        from: 0
        to: 360
        duration: g.p("spinMs", 1100)
        loops: Animation.Infinite
    }
    SequentialAnimation on flow {
        running: g.looping
        loops: Animation.Infinite
        PauseAnimation { duration: g.p("loopMs", 1800) * 0.4 }
        NumberAnimation { from: 0; to: 1; duration: g.p("flowMs", 700); easing.type: Easing.InOutSine }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        // Track (drawn closed by `ring`).
        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.alpha(g.deviceTop, 0.3)
            strokeWidth: g.u(g.p("stroke", 0.09))
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: g.u(0.5); centerY: g.u(0.5)
                radiusX: g.u(0.38); radiusY: g.u(0.38)
                startAngle: -90
                sweepAngle: 360 * Math.max(0.001, g.ring)
            }
        }
        // Progress / indeterminate arc.
        ShapePath {
            fillColor: "transparent"
            strokeColor: g.fillTop
            strokeWidth: g.u(g.p("stroke", 0.09))
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: g.u(0.5); centerY: g.u(0.5)
                radiusX: g.u(0.38); radiusY: g.u(0.38)
                startAngle: g.progress === null ? -90 + g.spin : -90
                sweepAngle: (g.progress === null ? 100 : 360 * G.clamp(g.progress, 0, 1)) * Math.max(0.001, g.ring)
            }
        }
    }
    // Arrow: drops in (`arrow`), then flows down — out the bottom while
    // fading, back in from the top (`flow` 0..1 = one pass).
    Item {
        id: arrowBox
        anchors.fill: parent
        readonly property real f: g.flow
        readonly property real dy: f < 0.5 ? g.u(0.2) * G.smooth(f * 2) : -g.u(0.2) * (1 - G.smooth((f - 0.5) * 2))
        opacity: G.smooth(g.arrow * 2) * (f < 0.5 ? 1 - G.smooth(f * 2) : G.smooth((f - 0.5) * 2))
        transform: Translate { y: -g.u(0.3) * (1 - g.arrow) + arrowBox.dy }
        GlyphLine {
            path: `M ${g.u(0.5)} ${g.u(0.29)} L ${g.u(0.5)} ${g.u(0.66)}`
                + ` M ${g.u(0.37)} ${g.u(0.54)} L ${g.u(0.5)} ${g.u(0.67)} L ${g.u(0.63)} ${g.u(0.54)}`
            color: g.deviceTop
            lineWidth: g.u(g.p("stroke", 0.09))
        }
    }
}
