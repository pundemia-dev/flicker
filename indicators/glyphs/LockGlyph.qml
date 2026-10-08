import QtQuick
import "../../components"
import "Glyph.js" as G

// VPN lock: the body pops in, the shackle (raised and open) drops into it
// on a bouncy spring — the body squashes on the click and the keyhole
// appears. Loop: a shine sweeps the body.
GlyphBase {
    id: g
    glyphName: "lock"

    property real pop: 0
    property real latch: 0
    property real squash: 0
    property real keyhole: 0
    property real shine: -1
    property bool clicked: false
    property bool looping: false

    onBegin: popAnim.start()
    onPopChanged: if (!latchAnim.running && g.latch === 0 && g.pop >= g.p("latchAt", 0.6)) latchAnim.start()
    onLatchChanged: if (!g.clicked && g.latch >= 0.97) {
        g.clicked = true;
        g.squash = 1;
        squashBack.start();
        keyholeAnim.start();
    }
    onKeyholeChanged: if (!g.looping && g.keyhole >= 1 - g.handoff) g.looping = true
    Spring { id: popAnim; target: g; property: "pop"; to: 1; stiffness: g.p("popStiffness", 7); damp: g.p("popDamping", 0.45); eps: 0.002 }
    Spring { id: latchAnim; target: g; property: "latch"; to: 1; stiffness: g.p("latchStiffness", 6); damp: g.p("latchDamping", 0.35); eps: 0.002 }
    Spring { id: keyholeAnim; target: g; property: "keyhole"; to: 1; stiffness: g.p("popStiffness", 7); damp: g.p("popDamping", 0.45); eps: 0.002 }
    Behavior on squash { Spring { stiffness: 9; damp: 0.35; eps: 0.002 } }
    Timer { id: squashBack; interval: 90; onTriggered: g.squash = 0 }
    SequentialAnimation on shine {
        running: g.looping
        loops: Animation.Infinite
        NumberAnimation { from: -0.2; to: 1.25; duration: g.p("shineMs", 700); easing.type: Easing.InOutSine }
        PauseAnimation { duration: g.p("loopMs", 1800) }
    }

    // Shackle: raised by (1 - latch), its right leg swung out while open.
    GlyphLine {
        readonly property real lift: g.u(0.17) * (1 - Math.min(1, g.latch))
        readonly property real swing: g.u(0.06) * (1 - Math.min(1, g.latch))
        path: `M ${g.u(0.33)} ${g.u(0.5) - lift} L ${g.u(0.33)} ${g.u(0.31) - lift}`
            + ` A ${g.u(0.17)} ${g.u(0.17)} 0 0 1 ${g.u(0.67) + swing} ${g.u(0.31) - lift}`
            + ` L ${g.u(0.67) + swing} ${g.u(0.42) - lift}`
        color: g.deviceTop
        lineWidth: g.u(g.p("stroke", 0.1))
        opacity: G.smooth(g.pop * 2)
    }
    Item {
        anchors.fill: parent
        opacity: G.smooth(g.pop * 2.5)
        transform: Scale {
            origin.x: g.u(0.5); origin.y: g.u(0.9)
            xScale: (0.35 + 0.65 * g.pop) * (1 + 0.05 * g.squash)
            yScale: (0.35 + 0.65 * g.pop) * (1 - 0.08 * g.squash)
        }
        GlyphFill {
            id: body
            path: G.rrect(g.u(0.19), g.u(0.44), g.u(0.62), g.u(0.47), g.u(0.11))
            colorTop: g.fillTop; colorBottom: g.fillBottom
            gy1: g.u(0.44); gy2: g.u(0.91)
            sheen: g.sheen
        }
        GlyphFill {
            path: G.circle(g.u(0.5), g.u(0.62), g.u(0.055) * Math.max(0, g.keyhole))
                + " " + G.rrect(g.u(0.5) - g.u(0.024) * Math.max(0, g.keyhole), g.u(0.63), g.u(0.048) * Math.max(0, g.keyhole), g.u(0.13) * Math.max(0, g.keyhole), g.u(0.02))
            colorTop: g.ink; colorBottom: g.ink
        }
        GlyphScreen {
            // Reused for the shine band only (no frame, glass = the body).
            fx: g.u(0.19); fy: g.u(0.44); fw: g.u(0.62); fh: g.u(0.47); fr: g.u(0.11)
            frameWidth: 0; inset: 0
            frameColor: "transparent"
            screenTop: "transparent"; screenBottom: "transparent"
            draw: 1; paint: 1; shine: g.shine
        }
    }
}
