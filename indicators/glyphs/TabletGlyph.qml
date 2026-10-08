import QtQuick
import "../../components"
import "Glyph.js" as G

// Tablet (iPad style): a wider bezel draws along its perimeter, the screen
// paints bottom-up in the tint, the camera dot pops in. Loop: a shine
// sweeps the glass.
GlyphBase {
    id: g
    glyphName: "tablet"

    property real draw: 0
    property real paint: 0
    property real cam: 0
    property real shine: -1
    property bool looping: false

    onBegin: drawAnim.start()
    onDrawChanged: if (!paintAnim.running && g.paint === 0 && g.draw >= g.p("paintAt", 0.75)) paintAnim.start()
    onPaintChanged: if (!camAnim.running && g.cam === 0 && g.paint >= g.p("detailAt", 0.8)) camAnim.start()
    onCamChanged: if (!g.looping && g.cam >= 1 - g.handoff) g.looping = true
    Spring { id: drawAnim; target: g; property: "draw"; to: 1; stiffness: g.p("revealStiffness", 6); damp: 1; eps: 0.002 }
    Spring { id: paintAnim; target: g; property: "paint"; to: 1; stiffness: g.p("revealStiffness", 6); damp: 1; eps: 0.002 }
    Spring { id: camAnim; target: g; property: "cam"; to: 1; stiffness: g.p("popStiffness", 7); damp: g.p("popDamping", 0.45); eps: 0.002 }
    SequentialAnimation on shine {
        running: g.looping
        loops: Animation.Infinite
        NumberAnimation { from: -0.2; to: 1.25; duration: g.p("shineMs", 700); easing.type: Easing.InOutSine }
        PauseAnimation { duration: g.p("loopMs", 1800) }
    }

    GlyphScreen {
        fx: g.u(0.17); fy: g.u(0.1); fw: g.u(0.66); fh: g.u(0.8); fr: g.u(0.09)
        frameWidth: g.u(g.p("frame", 0.07))
        inset: g.u(0.06)
        frameColor: g.deviceTop
        screenTop: g.fillTop; screenBottom: g.fillBottom
        draw: g.draw; paint: g.paint; shine: g.shine
    }
    GlyphFill {
        path: G.circle(g.u(0.5), g.u(0.1), g.u(0.022) * Math.max(0, g.cam))
        colorTop: g.ink; colorBottom: g.ink
    }
}
