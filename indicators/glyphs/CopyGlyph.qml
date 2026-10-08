import QtQuick
import "../../components"
import "Glyph.js" as G

// Copied: the original page pops in, its copy slides out of it to the
// bottom-right on a spring (the "copy" motion), then a check mark draws on
// the copy. Loop: the copy pulses and the check redraws now and then.
GlyphBase {
    id: g
    glyphName: "copy"

    property real pop: 0
    property real slide: 0
    property real check: 0
    property real pulse: 0
    property bool looping: false

    onBegin: popAnim.start()
    onPopChanged: if (!slideAnim.running && g.slide === 0 && g.pop >= g.p("slideAt", 0.5)) slideAnim.start()
    onSlideChanged: if (!checkAnim.running && g.check === 0 && g.slide >= g.p("checkAt", 0.75)) {
        checkAnim.to = 1;
        checkAnim.start();
    }
    onCheckChanged: if (!g.looping && g.check >= 1 - g.handoff) g.looping = true
    Spring { id: popAnim; target: g; property: "pop"; to: 1; stiffness: g.p("popStiffness", 7); damp: g.p("popDamping", 0.45); eps: 0.002 }
    Spring { id: slideAnim; target: g; property: "slide"; to: 1; stiffness: g.p("revealStiffness", 6); damp: g.p("slideDamping", 0.55); eps: 0.002 }
    Spring { id: checkAnim; target: g; property: "check"; stiffness: g.p("revealStiffness", 6); damp: 1; eps: 0.002 }
    Behavior on pulse { Spring { stiffness: 7; damp: 0.4; eps: 0.002 } }
    Timer { id: pulseBack; interval: 130; onTriggered: g.pulse = 0 }
    SequentialAnimation {
        running: g.looping
        loops: Animation.Infinite
        PauseAnimation { duration: g.p("loopMs", 1800) }
        NumberAnimation { target: g; property: "check"; to: 0; duration: 160; easing.type: Easing.InSine }
        ScriptAction { script: { g.pulse = 1; pulseBack.restart(); checkAnim.to = 1; checkAnim.start(); } }
        PauseAnimation { duration: 500 }
    }

    // Original (behind, neutral).
    GlyphFill {
        opacity: 0.75 * G.smooth(g.pop * 2.5)
        transform: Scale { origin.x: g.u(0.37); origin.y: g.u(0.36); xScale: 0.4 + 0.6 * g.pop; yScale: 0.4 + 0.6 * g.pop }
        path: G.rrect(g.u(0.13), g.u(0.09), g.u(0.47), g.u(0.54), g.u(0.1))
        colorTop: g.deviceTop; colorBottom: g.deviceBottom
        gy1: g.u(0.09); gy2: g.u(0.63)
    }
    // The copy: slides out of the original into place.
    Item {
        anchors.fill: parent
        opacity: G.smooth(g.slide * 3)
        transform: [
            Translate { x: -g.u(0.23) * (1 - g.slide); y: -g.u(0.24) * (1 - g.slide) },
            Scale { origin.x: g.u(0.61); origin.y: g.u(0.62); xScale: 1 + 0.07 * g.pulse; yScale: 1 + 0.07 * g.pulse }
        ]
        GlyphFill {
            path: G.rrect(g.u(0.36), g.u(0.33), g.u(0.5), g.u(0.58), g.u(0.1))
            colorTop: g.fillTop; colorBottom: g.fillBottom
            gy1: g.u(0.33); gy2: g.u(0.91)
            sheen: g.sheen
        }
        GlyphLine {
            path: G.svg(G.trim([[g.u(0.47), g.u(0.63)], [g.u(0.57), g.u(0.73)], [g.u(0.75), g.u(0.5)]], g.check), false)
            color: g.deviceTop
            lineWidth: g.u(g.p("stroke", 0.09))
            opacity: g.check > 0.01 ? 1 : 0
        }
    }
}
