import QtQuick
import "../../components"
import "Glyph.js" as G

// Battery (horizontal, iOS status-bar style): the outline draws round from
// the top centre, the terminal nub pops, then the charge fills left to
// right up to `args.level` (0..1, default full) on an under-damped spring.
// Loop: full = a shine sweeps the charge; `args.critical` = the charge
// blinks (low-battery warning).
GlyphBase {
    id: g
    glyphName: "battery"

    readonly property real level: G.clamp(g.args?.level ?? 1, 0, 1)
    readonly property bool critical: !!g.args?.critical
    property real draw: 0
    property real nub: 0
    property real fill: 0
    property real shine: -1
    property real blink: 1
    property bool looping: false

    onBegin: drawAnim.start()
    onDrawChanged: {
        if (!nubAnim.running && g.nub === 0 && g.draw >= g.p("nubAt", 0.7))
            nubAnim.start();
        if (!fillAnim.running && g.fill === 0 && g.draw >= g.p("fillAt", 0.85)) {
            fillAnim.to = Math.max(g.p("minLevel", 0.1), g.level);
            fillAnim.start();
        }
    }
    onFillChanged: if (!g.looping && g.fill >= fillAnim.to - g.handoff) g.looping = true
    Spring { id: drawAnim; target: g; property: "draw"; to: 1; stiffness: g.p("revealStiffness", 6); damp: 1; eps: 0.002 }
    Spring { id: nubAnim; target: g; property: "nub"; to: 1; stiffness: g.p("popStiffness", 7); damp: g.p("popDamping", 0.45); eps: 0.002 }
    Spring { id: fillAnim; target: g; property: "fill"; stiffness: g.p("fillStiffness", 3.5); damp: g.p("fillDamping", 0.35); eps: 0.002 }
    SequentialAnimation on shine {
        running: g.looping && !g.critical
        loops: Animation.Infinite
        PauseAnimation { duration: g.p("loopMs", 1800) * 0.5 }
        NumberAnimation { from: -0.2; to: 1.25; duration: g.p("shineMs", 700); easing.type: Easing.InOutSine }
        PauseAnimation { duration: g.p("loopMs", 1800) * 0.5 }
    }
    SequentialAnimation on blink {
        running: g.looping && g.critical
        loops: Animation.Infinite
        NumberAnimation { to: 0.25; duration: g.p("blinkMs", 520); easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: g.p("blinkMs", 520); easing.type: Easing.InOutSine }
        PauseAnimation { duration: g.p("blinkPauseMs", 500) }
    }

    readonly property real bx: g.u(0.06)
    readonly property real by: g.u(0.3)
    readonly property real bw: g.u(0.78)
    readonly property real bh: g.u(0.4)
    readonly property real br: g.u(0.11)
    readonly property real stroke: g.u(g.p("stroke", 0.075))
    readonly property real pad: g.stroke / 2 + g.u(g.p("gap", 0.05))
    readonly property real ix: g.bx + g.pad
    readonly property real iy: g.by + g.pad
    readonly property real iw: g.bw - 2 * g.pad
    readonly property real ih: g.bh - 2 * g.pad
    readonly property real fw: g.iw * G.clamp(g.fill, 0, 1.04)

    GlyphLine {
        path: G.svg(G.trim(G.rrectPts(g.bx, g.by, g.bw, g.bh, g.br, 6), g.draw), g.draw >= 1)
        color: g.deviceTop
        lineWidth: g.stroke
        opacity: 0.9
    }
    // Terminal nub.
    GlyphFill {
        opacity: G.smooth(g.nub * 2)
        path: G.rrect(g.bx + g.bw + g.u(0.025), g.u(0.42), g.u(0.065) * Math.max(0, g.nub), g.u(0.16), g.u(0.03))
        colorTop: g.deviceTop; colorBottom: g.deviceBottom
    }
    // Charge.
    GlyphFill {
        opacity: g.blink
        path: g.fw > 0.3 ? G.rrect(g.ix, g.iy, g.fw, g.ih, Math.min(g.br - g.pad, g.fw / 2)) : ""
        colorTop: g.fillTop; colorBottom: g.fillBottom
        gy1: g.iy; gy2: g.iy + g.ih
        sheen: g.sheen
    }
    // Shine band over the charge (full battery).
    GlyphFill {
        readonly property real sx: g.ix + (g.iw + g.u(0.2)) * g.shine - g.u(0.1)
        visible: g.shine > -0.15 && g.shine < 1.2 && g.fw > 0.3
        opacity: 0.38
        // Corners clamped into the charge (the band squeezes at its ends).
        readonly property real x0: g.ix + g.u(0.02)
        readonly property real x1: g.ix + g.fw - g.u(0.02)
        path: G.svg([[sx, g.iy + g.u(0.02)], [sx + g.u(0.08), g.iy + g.u(0.02)], [sx + g.u(0.02), g.iy + g.ih - g.u(0.02)], [sx - g.u(0.06), g.iy + g.ih - g.u(0.02)]]
            .map(q => [G.clamp(q[0], x0, Math.max(x0, x1)), q[1]]), true)
        colorTop: "#FFFFFF"; colorBottom: "#FFFFFF"
    }
}
