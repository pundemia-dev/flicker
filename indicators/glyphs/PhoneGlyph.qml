import QtQuick
import "../../components"
import "Glyph.js" as G

// Phone (iPhone style): the bezel draws along its perimeter, the screen
// paints bottom-up in the tint, the Dynamic Island pops in. Loop: the
// island expands like a live activity and shrinks back; a shine sweeps the
// glass now and then.
GlyphBase {
    id: g
    glyphName: "phone"

    property real draw: 0
    property real paint: 0
    property real island: 0
    property real expand: 0
    property real shine: -1
    property bool looping: false

    onBegin: drawAnim.start()
    onDrawChanged: if (!paintAnim.running && g.paint === 0 && g.draw >= g.p("paintAt", 0.75)) paintAnim.start()
    onPaintChanged: if (!islandAnim.running && g.island === 0 && g.paint >= g.p("detailAt", 0.8)) islandAnim.start()
    onIslandChanged: if (!g.looping && g.island >= 1 - g.handoff) g.looping = true
    Spring { id: drawAnim; target: g; property: "draw"; to: 1; stiffness: g.p("revealStiffness", 6); damp: 1; eps: 0.002 }
    Spring { id: paintAnim; target: g; property: "paint"; to: 1; stiffness: g.p("revealStiffness", 6); damp: 1; eps: 0.002 }
    Spring { id: islandAnim; target: g; property: "island"; to: 1; stiffness: g.p("popStiffness", 7); damp: g.p("popDamping", 0.45); eps: 0.002 }
    Behavior on expand { Spring { stiffness: g.p("popStiffness", 7); damp: 0.55; eps: 0.002 } }
    Timer {
        running: g.looping
        repeat: true
        interval: g.p("loopMs", 1800)
        onTriggered: {
            g.expand = g.expand > 0.5 ? 0 : 1;
            if (g.expand > 0.5)
                shineAnim.restart();
        }
    }
    NumberAnimation { id: shineAnim; target: g; property: "shine"; from: -0.2; to: 1.25; duration: g.p("shineMs", 700); easing.type: Easing.InOutSine }

    GlyphScreen {
        fx: g.u(0.29); fy: g.u(0.07); fw: g.u(0.42); fh: g.u(0.86); fr: g.u(0.11)
        frameWidth: g.u(g.p("frame", 0.07))
        inset: g.u(0.06)
        frameColor: g.deviceTop
        screenTop: g.fillTop; screenBottom: g.fillBottom
        draw: g.draw; paint: g.paint; shine: g.shine
    }
    // Dynamic Island.
    GlyphFill {
        readonly property real w: g.u(0.12 + 0.11 * g.expand) * Math.max(0, g.island)
        readonly property real h: g.u(0.045 + 0.025 * g.expand) * Math.max(0, g.island)
        path: G.rrect(g.u(0.5) - w / 2, g.u(0.165) - h / 2, w, h, h / 2)
        colorTop: g.ink; colorBottom: g.ink
    }
}
