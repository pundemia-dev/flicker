import QtQuick
import QtQuick.Shapes
import "../../components"
import "Glyph.js" as G

// Watch (Apple Watch style, no band — user): a big rounded square case
// with a dark screen and the digital crown on the right. Reveal: the case
// pops, an activity ring in the tint sweeps closed on the screen. Loop: the ring closes again with a
// little bump, fades and re-sweeps.
GlyphBase {
    id: g
    glyphName: "watch"

    property real pop: 0
    property real ring: 0
    property real bump: 0
    property bool looping: false

    onBegin: popAnim.start()
    onPopChanged: if (!ringAnim.running && g.ring === 0 && g.pop >= g.p("ringAt", 0.7)) {
        ringAnim.to = 1;
        ringAnim.start();
    }
    onRingChanged: if (!g.looping && g.ring >= 1 - g.handoff) {
        g.looping = true;
        g.bump = 1;
        bumpBack.start();
    }
    Spring { id: popAnim; target: g; property: "pop"; to: 1; stiffness: g.p("popStiffness", 7); damp: g.p("popDamping", 0.45); eps: 0.002 }
    Spring { id: ringAnim; target: g; property: "ring"; stiffness: g.p("ringStiffness", 4); damp: 1; eps: 0.002 }
    Behavior on bump { Spring { stiffness: 8; damp: 0.35; eps: 0.002 } }
    Timer { id: bumpBack; interval: 120; onTriggered: g.bump = 0 }
    // Loop: hold the closed ring, fade it, sweep again.
    SequentialAnimation {
        running: g.looping
        loops: Animation.Infinite
        PauseAnimation { duration: g.p("loopMs", 1800) }
        NumberAnimation { target: g; property: "ring"; to: 0; duration: 260; easing.type: Easing.InOutSine }
        ScriptAction { script: { ringAnim.to = 1; ringAnim.start(); } }
        PauseAnimation { duration: 700 }
        ScriptAction { script: { g.bump = 1; bumpBack.restart(); } }
    }

    Item {
        anchors.fill: parent
        opacity: G.smooth(g.pop * 2.5)
        // Shifted left a little: the crown sticks out on the right.
        transform: Scale {
            origin.x: g.u(0.53); origin.y: g.u(0.5)
            xScale: (0.3 + 0.7 * g.pop) * (1 + 0.06 * g.bump) * g.p("scale", 1.3)
            yScale: (0.3 + 0.7 * g.pop) * (1 + 0.06 * g.bump) * g.p("scale", 1.3)
        }
        GlyphFill {
            path: G.rrect(g.u(0.77), g.u(0.36), g.u(0.06), g.u(0.15), g.u(0.025))
            colorTop: g.deviceTop; colorBottom: g.deviceBottom
        }
        GlyphFill {
            path: G.rrect(g.u(0.22), g.u(0.17), g.u(0.56), g.u(0.66), g.u(0.17))
            colorTop: g.deviceTop; colorBottom: g.deviceBottom
            gy1: g.u(0.17); gy2: g.u(0.83)
            sheen: g.sheen
        }
        GlyphFill {
            path: G.rrect(g.u(0.27), g.u(0.22), g.u(0.46), g.u(0.56), g.u(0.13))
            colorTop: g.ink; colorBottom: g.ink
        }
        // Activity ring: track + sweep.
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.alpha(g.color, 0.28)
                strokeWidth: g.u(0.07)
                PathAngleArc {
                    centerX: g.u(0.5); centerY: g.u(0.5)
                    radiusX: g.u(0.14); radiusY: g.u(0.14)
                    startAngle: 0; sweepAngle: 360
                }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: g.fillTop
                strokeWidth: g.u(0.07)
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: g.u(0.5); centerY: g.u(0.5)
                    radiusX: g.u(0.14); radiusY: g.u(0.14)
                    startAngle: -90
                    sweepAngle: 360 * Math.max(0.001, Math.min(1, g.ring))
                }
            }
        }
    }
}
