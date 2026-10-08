import QtQuick
import QtQuick.Shapes
import "../../components"
import "Glyph.js" as G

// AirPods Max (and any over-ear headphones): a thick canopy headband over
// two tall rounded cups with a darker cushion on the inner side. Reveal:
// the band draws out from the top centre to both sides (the ghost head
// idea), then the cups drop down out of its ends on a bouncy spring.
// Loop: sound arcs radiate out of both cups.
GlyphBase {
    id: g
    glyphName: "airpodsMax"

    property real band: 0
    property real cups: 0
    property bool looping: false

    onBegin: bandAnim.start()
    onBandChanged: if (!cupsAnim.running && g.cups === 0 && g.band >= g.p("cupsAt", 0.6)) cupsAnim.start()
    onCupsChanged: if (!g.looping && g.cups >= 1 - g.handoff) g.looping = true
    Spring { id: bandAnim; target: g; property: "band"; to: 1; stiffness: g.p("revealStiffness", 6); damp: 1; eps: 0.002 }
    Spring { id: cupsAnim; target: g; property: "cups"; to: 1; stiffness: g.p("popStiffness", 7); damp: g.p("popDamping", 0.45); eps: 0.002 }

    // Headband: an arc around (0.5, 0.58), r 0.36, spanning 200..340 deg,
    // drawn out from 270 by `band`.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeColor: g.deviceTop
            strokeWidth: g.u(g.p("bandWidth", 0.11))
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: g.u(0.5); centerY: g.u(0.58)
                radiusX: g.u(0.36); radiusY: g.u(0.36)
                startAngle: 270 - 70 * Math.max(0.01, g.band)
                sweepAngle: 140 * Math.max(0.01, g.band)
            }
        }
    }

    Repeater {
        model: [-1, 1] // left, right
        delegate: Item {
            id: cup
            required property int modelData
            readonly property int side: cup.modelData
            function mx(x: real): real {
                return cup.side < 0 ? x : 1 - x;
            }
            anchors.fill: parent
            opacity: G.smooth(g.cups * 2.5)
            transform: [
                Scale {
                    origin.x: g.u(cup.mx(0.19)); origin.y: g.u(0.44)
                    yScale: 0.4 + 0.6 * g.cups
                },
                Translate { y: -g.u(0.1) * (1 - g.cups) }
            ]
            GlyphFill {
                path: G.rrect(g.u(Math.min(cup.mx(0.08), cup.mx(0.3))), g.u(0.44), g.u(0.22), g.u(0.42), g.u(0.1))
                colorTop: g.deviceTop; colorBottom: g.deviceBottom
                gy1: g.u(0.44); gy2: g.u(0.86)
                sheen: g.sheen
            }
            GlyphFill {
                path: G.rrect(g.u(Math.min(cup.mx(0.25), cup.mx(0.31))), g.u(0.5), g.u(0.06), g.u(0.3), g.u(0.03))
                colorTop: Qt.lighter(g.ink, 1.6); colorBottom: g.ink
            }
        }
    }

    GlyphWaves {
        cx: g.u(0.19); cy: g.u(0.65)
        r0: g.u(0.16); spread: g.u(0.07)
        angle: 180; halfSpan: 42
        color: g.color
        lineWidth: g.u(0.065)
        period: g.p("waveMs", 1400)
        running: g.looping
    }
    GlyphWaves {
        cx: g.u(0.81); cy: g.u(0.65)
        r0: g.u(0.16); spread: g.u(0.07)
        angle: 0; halfSpan: 42
        color: g.color
        lineWidth: g.u(0.065)
        period: g.p("waveMs", 1400)
        running: g.looping
    }
}
