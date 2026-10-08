import QtQuick
import "../../components"
import "Glyph.js" as G

// Generic Bluetooth device: the rune draws along its own path (a stroke
// trimmed by length, like pacman's line), then signal arcs pulse out on
// both sides (Wi-Fi style).
GlyphBase {
    id: g
    glyphName: "bluetooth"

    property real draw: 0
    property bool looping: false
    readonly property var rune: [[0.33, 0.31], [0.67, 0.66], [0.5, 0.84], [0.5, 0.16], [0.67, 0.34], [0.33, 0.69]].map(q => [g.u(q[0]), g.u(q[1])])

    onBegin: drawAnim.start()
    onDrawChanged: if (!g.looping && g.draw >= 1 - g.handoff) g.looping = true
    Spring { id: drawAnim; target: g; property: "draw"; to: 1; stiffness: g.p("revealStiffness", 6); damp: 1; eps: 0.002 }

    GlyphLine {
        path: G.svg(G.trim(g.rune, g.draw), false)
        color: g.fillTop
        lineWidth: g.u(g.p("stroke", 0.1))
    }
    GlyphWaves {
        cx: g.u(0.5); cy: g.u(0.5)
        r0: g.u(0.33); spread: g.u(0.13)
        angle: 0
        color: g.color
        lineWidth: g.u(0.07)
        period: g.p("waveMs", 1400)
        running: g.looping
    }
    GlyphWaves {
        cx: g.u(0.5); cy: g.u(0.5)
        r0: g.u(0.33); spread: g.u(0.13)
        angle: 180
        color: g.color
        lineWidth: g.u(0.07)
        period: g.p("waveMs", 1400)
        running: g.looping
    }
}
