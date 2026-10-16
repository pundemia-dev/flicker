import QtQuick
import "../../components"
import "Glyph.js" as G

// Wi‑Fi fan. Connected (default): the dot pops, then the three arcs open
// out from the middle one after another (inner first). Loop: a brightness
// pulse travels outward through the arcs. `args.lost`: the arcs start lit
// and go out from the OUTER one inwards, the dot dims; loop: a faint
// "searching" sweep (inner -> outer) now and then.
GlyphBase {
    id: g
    glyphName: "wifi"

    readonly property bool lost: !!g.args?.lost
    property real dot: 0
    // 0..arcs: arc i opens over [i, i + 1] (connected) / closes (lost).
    property real reveal: 0
    property real pulse: -1
    property bool looping: false
    readonly property int arcs: 3

    onBegin: {
        if (g.lost) {
            g.dot = 1;
            g.reveal = g.arcs;
            fadeAnim.to = 0;
            fadeAnim.start();
        } else {
            dotAnim.start();
        }
    }
    onDotChanged: if (!g.lost && !revealAnim.running && g.reveal === 0 && g.dot >= g.p("arcsAt", 0.55)) revealAnim.start()
    onRevealChanged: {
        if (g.looping)
            return;
        if (!g.lost && g.reveal >= g.arcs - g.handoff)
            g.looping = true;
        if (g.lost && g.reveal <= g.handoff)
            g.looping = true;
    }
    Spring { id: dotAnim; target: g; property: "dot"; to: 1; stiffness: g.p("popStiffness", 7); damp: g.p("popDamping", 0.45); eps: 0.002 }
    Spring { id: revealAnim; target: g; property: "reveal"; to: g.arcs; stiffness: g.p("revealStiffness", 6); damp: 1; eps: 0.004 }
    Spring { id: fadeAnim; target: g; property: "reveal"; stiffness: g.p("revealStiffness", 6) * 0.8; damp: 1; eps: 0.004 }
    SequentialAnimation on pulse {
        running: g.looping
        loops: Animation.Infinite
        PauseAnimation { duration: g.p("loopMs", 1800) }
        NumberAnimation { from: -0.5; to: g.arcs + 0.5; duration: g.p("pulseMs", 900); easing.type: Easing.InOutSine }
        PropertyAction { value: -1 }
    }

    // Fan centre near the bottom; arcs spread ±halfSpan around straight up.
    readonly property real cx: g.u(0.5)
    readonly property real cy: g.u(0.8)
    readonly property real halfSpan: g.p("halfSpan", 45)
    readonly property real stroke: g.u(g.p("stroke", 0.11))
    readonly property real dimLevel: g.p("dim", 0.28)

    // Lit level of arc i: 1 = fully drawn and bright.
    function amount(i: int): real {
        return G.smooth(g.reveal - i);
    }
    function pulseOf(i: int): real {
        return g.pulse < -0.4 ? 0 : Math.max(0, 1 - Math.abs(g.pulse - i - 0.5) * 1.6);
    }

    Repeater {
        model: g.arcs
        delegate: Item {
            id: arc
            required property int index
            readonly property real r: g.u(0.2 + 0.18 * arc.index)
            readonly property real a: g.amount(arc.index)
            anchors.fill: parent
            // Faint track: lost = what was there; also the searching sweep.
            GlyphLine {
                visible: g.lost
                opacity: g.dimLevel * (1 - arc.a) + 0.6 * g.pulseOf(arc.index)
                path: G.svg(G.arcPts(g.cx, g.cy, arc.r, -90 - g.halfSpan, -90 + g.halfSpan, 14), false)
                color: g.fillBottom
                lineWidth: g.stroke
            }
            GlyphLine {
                // Connected: opens from the middle; lost: shrinks + fades.
                readonly property real half: g.halfSpan * Math.max(0.02, g.lost ? 0.6 + 0.4 * arc.a : arc.a)
                opacity: g.lost ? arc.a : Math.min(1, G.smooth(arc.a * 3)) * (0.78 + 0.22 * g.pulseOf(arc.index))
                path: G.svg(G.arcPts(g.cx, g.cy, arc.r, -90 - half, -90 + half, 14), false)
                color: Qt.tint(g.fillTop, Qt.rgba(1, 1, 1, 0.35 * g.pulseOf(arc.index)))
                lineWidth: g.stroke
            }
        }
    }
    GlyphFill {
        opacity: g.lost ? 0.45 + 0.55 * G.smooth(g.reveal / g.arcs) : 1
        path: G.circle(g.cx, g.cy, g.u(0.075) * Math.max(0, g.dot))
        colorTop: g.fillTop; colorBottom: g.color
    }
}
