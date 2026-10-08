import QtQuick
import "../../components"
import "Glyph.js" as G

// System error (failed units): a rounded warning triangle draws along its
// outline, fills, the exclamation bar drops in and the dot bounces under
// it. Loop: an iOS-style "no" shake now and then.
GlyphBase {
    id: g
    glyphName: "error"

    property real draw: 0
    property real fill: 0
    property real bar: 0
    property real dot: 0
    property real shake: 0
    property bool looping: false

    onBegin: drawAnim.start()
    onDrawChanged: if (!fillAnim.running && g.fill === 0 && g.draw >= g.p("fillAt", 0.7)) fillAnim.start()
    onFillChanged: if (!barAnim.running && g.bar === 0 && g.fill >= g.p("barAt", 0.5)) barAnim.start()
    onBarChanged: if (!dotAnim.running && g.dot === 0 && g.bar >= g.p("dotAt", 0.6)) dotAnim.start()
    onDotChanged: if (!g.looping && g.dot >= 1 - g.handoff) g.looping = true
    Spring { id: drawAnim; target: g; property: "draw"; to: 1; stiffness: g.p("revealStiffness", 6); damp: 1; eps: 0.002 }
    Spring { id: fillAnim; target: g; property: "fill"; to: 1; stiffness: g.p("revealStiffness", 6); damp: 1; eps: 0.002 }
    Spring { id: barAnim; target: g; property: "bar"; to: 1; stiffness: g.p("popStiffness", 7); damp: g.p("popDamping", 0.45); eps: 0.002 }
    Spring { id: dotAnim; target: g; property: "dot"; to: 1; stiffness: g.p("popStiffness", 7); damp: 0.35; eps: 0.002 }
    SequentialAnimation on shake {
        running: g.looping
        loops: Animation.Infinite
        PauseAnimation { duration: g.p("loopMs", 1800) }
        NumberAnimation { to: 1; duration: 60; easing.type: Easing.OutSine }
        NumberAnimation { to: -0.8; duration: 110; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.5; duration: 100; easing.type: Easing.InOutSine }
        NumberAnimation { to: -0.25; duration: 90; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: 80; easing.type: Easing.OutSine }
    }

    // Rounded triangle: corners cut by `c` and bridged by quadratics.
    readonly property var tri: [[0.5, 0.11], [0.92, 0.86], [0.08, 0.86]].map(q => [g.u(q[0]), g.u(q[1])])
    function rounded(pts: var, c: real): string {
        const n = pts.length, lerp = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
        const cut = (a, b) => c / Math.hypot(b[0] - a[0], b[1] - a[1]);
        let p = "";
        for (let i = 0; i < n; i++) {
            const prev = pts[(i + n - 1) % n], cur = pts[i], next = pts[(i + 1) % n];
            const a = lerp(cur, prev, cut(cur, prev)), b = lerp(cur, next, cut(cur, next));
            p += (i === 0 ? `M ${a[0]} ${a[1]}` : ` L ${a[0]} ${a[1]}`) + ` Q ${cur[0]} ${cur[1]} ${b[0]} ${b[1]}`;
        }
        return p + " Z";
    }

    Item {
        anchors.fill: parent
        transform: Translate { x: g.u(g.p("shakeAmp", 0.07)) * g.shake }
        GlyphFill {
            opacity: g.fill
            path: g.rounded(g.tri, g.u(0.1))
            colorTop: g.fillTop; colorBottom: g.fillBottom
            gy1: g.u(0.11); gy2: g.u(0.86)
            sheen: g.sheen
        }
        GlyphLine {
            opacity: 1 - g.fill
            path: G.svg(G.trim(g.tri.concat([g.tri[0]]), g.draw), false)
            color: g.fillTop
            lineWidth: g.u(g.p("stroke", 0.09))
        }
        // Exclamation: bar drops from above, dot bounces in.
        GlyphFill {
            opacity: G.smooth(g.bar * 2)
            path: G.rrect(g.u(0.455), g.u(0.36) - g.u(0.25) * (1 - g.bar), g.u(0.09), g.u(0.27), g.u(0.045))
            colorTop: g.deviceTop; colorBottom: g.deviceTop
        }
        GlyphFill {
            path: G.circle(g.u(0.5), g.u(0.73), g.u(0.055) * Math.max(0, g.dot))
            colorTop: g.deviceTop; colorBottom: g.deviceTop
        }
    }
}
