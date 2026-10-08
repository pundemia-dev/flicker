import QtQuick
import "../../components"
import "Glyph.js" as G

// Speaker (HomePod mini style): a soft rounded body with a dark top
// surface and a glowing light in the tint (Siri-like). Reveal: the body
// rises out of its base (scales up from the bottom, slight overshoot), then
// the top light fades in. Loop: the light breathes and sound arcs leave
// both sides.
GlyphBase {
    id: g
    glyphName: "speaker"

    property real rise: 0
    property real glowIn: 0
    property real breath: 0
    property bool looping: false

    onBegin: riseAnim.start()
    onRiseChanged: if (!glowAnim.running && g.glowIn === 0 && g.rise >= g.p("glowAt", 0.7)) glowAnim.start()
    onGlowInChanged: if (!g.looping && g.glowIn >= 1 - g.handoff) g.looping = true
    Spring { id: riseAnim; target: g; property: "rise"; to: 1; stiffness: g.p("popStiffness", 7); damp: g.p("popDamping", 0.45); eps: 0.002 }
    Spring { id: glowAnim; target: g; property: "glowIn"; to: 1; stiffness: g.p("revealStiffness", 6); damp: 1; eps: 0.002 }
    SequentialAnimation on breath {
        running: g.looping
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: g.p("breathMs", 1100); easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0; duration: g.p("breathMs", 1100); easing.type: Easing.InOutSine }
    }

    Item {
        anchors.fill: parent
        opacity: G.smooth(g.rise * 3)
        transform: Scale {
            origin.x: g.u(0.5); origin.y: g.u(0.88)
            xScale: 0.75 + 0.25 * g.rise
            yScale: g.rise
        }
        GlyphFill {
            path: G.rrect(g.u(0.15), g.u(0.26), g.u(0.7), g.u(0.62), g.u(0.3))
            colorTop: g.deviceTop; colorBottom: g.deviceBottom
            gy1: g.u(0.26); gy2: g.u(0.88)
            sheen: g.sheen
        }
        GlyphFill {
            path: G.ellipse(g.u(0.5), g.u(0.31), g.u(0.27), g.u(0.07))
            colorTop: g.ink; colorBottom: Qt.lighter(g.ink, 1.5)
        }
        GlyphFill {
            opacity: g.glowIn * (0.65 + 0.35 * g.breath)
            path: G.ellipse(g.u(0.5), g.u(0.31), g.u(0.1 + 0.04 * g.breath), g.u(0.035 + 0.012 * g.breath))
            colorTop: g.fillTop; colorBottom: g.color
        }
    }

    GlyphWaves {
        cx: g.u(0.5); cy: g.u(0.58)
        r0: g.u(0.38); spread: g.u(0.1)
        angle: 0; halfSpan: 32
        color: g.color
        lineWidth: g.u(0.065)
        period: g.p("waveMs", 1400)
        running: g.looping
    }
    GlyphWaves {
        cx: g.u(0.5); cy: g.u(0.58)
        r0: g.u(0.38); spread: g.u(0.1)
        angle: 180; halfSpan: 32
        color: g.color
        lineWidth: g.u(0.065)
        period: g.p("waveMs", 1400)
        running: g.looping
    }
}
