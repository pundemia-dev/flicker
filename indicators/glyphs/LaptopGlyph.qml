import QtQuick
import "../../components"
import "Glyph.js" as G

// Laptop (MacBook style): the base slides up into place, the lid swings
// open from the hinge (scales up from the bottom, overshooting like a real
// lid), its bezel draws and the screen paints bottom-up. Loop: a shine
// sweeps the screen.
GlyphBase {
    id: g
    glyphName: "laptop"

    property real base: 0
    property real lid: 0
    property real paint: 0
    property real shine: -1
    property bool looping: false

    onBegin: baseAnim.start()
    onBaseChanged: if (!lidAnim.running && g.lid === 0 && g.base >= g.p("lidAt", 0.5)) lidAnim.start()
    onLidChanged: if (!paintAnim.running && g.paint === 0 && g.lid >= g.p("paintAt", 0.75)) paintAnim.start()
    onPaintChanged: if (!g.looping && g.paint >= 1 - g.handoff) g.looping = true
    Spring { id: baseAnim; target: g; property: "base"; to: 1; stiffness: g.p("revealStiffness", 6); damp: 1; eps: 0.002 }
    Spring { id: lidAnim; target: g; property: "lid"; to: 1; stiffness: g.p("popStiffness", 7); damp: g.p("lidDamping", 0.5); eps: 0.002 }
    Spring { id: paintAnim; target: g; property: "paint"; to: 1; stiffness: g.p("revealStiffness", 6); damp: 1; eps: 0.002 }
    SequentialAnimation on shine {
        running: g.looping
        loops: Animation.Infinite
        NumberAnimation { from: -0.2; to: 1.25; duration: g.p("shineMs", 700); easing.type: Easing.InOutSine }
        PauseAnimation { duration: g.p("loopMs", 1800) }
    }

    // Lid: hinged at the base top (y 0.69).
    Item {
        anchors.fill: parent
        opacity: G.smooth(g.lid * 3)
        transform: Scale { origin.x: g.u(0.5); origin.y: g.u(0.69); yScale: Math.max(0, g.lid) }
        GlyphFill {
            path: G.rrect(g.u(0.16), g.u(0.16), g.u(0.68), g.u(0.53), g.u(0.06))
            colorTop: g.deviceTop; colorBottom: g.deviceBottom
            gy1: g.u(0.16); gy2: g.u(0.69)
        }
        GlyphScreen {
            fx: g.u(0.16); fy: g.u(0.16); fw: g.u(0.68); fh: g.u(0.53); fr: g.u(0.06)
            frameWidth: 0
            inset: g.u(0.055)
            frameColor: "transparent"
            screenTop: g.fillTop; screenBottom: g.fillBottom
            draw: 1; paint: g.paint; shine: g.shine
        }
    }
    // Base with the thumb notch.
    Item {
        anchors.fill: parent
        opacity: G.smooth(g.base * 2)
        transform: Translate { y: g.u(0.2) * (1 - g.base) }
        GlyphFill {
            path: G.rrect(g.u(0.05), g.u(0.69), g.u(0.9), g.u(0.085), g.u(0.04))
            colorTop: g.deviceTop; colorBottom: g.deviceBottom
            gy1: g.u(0.69); gy2: g.u(0.775)
        }
        GlyphFill {
            path: G.rrect(g.u(0.42), g.u(0.69), g.u(0.16), g.u(0.028), g.u(0.014))
            colorTop: Qt.darker(g.deviceBottom, 1.3); colorBottom: Qt.darker(g.deviceBottom, 1.3)
        }
    }
}
