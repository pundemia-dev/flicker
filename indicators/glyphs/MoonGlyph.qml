import QtQuick
import "../../components"
import "Glyph.js" as G

// Do Not Disturb / Focus moon (as big as pacman: R 0.47 of the size): a full disc pops in, then a shadow disc
// slides over it from the top-right and carves the crescent (an eclipse).
// Loop: three little stars twinkle in the bite and the moon rocks gently.
// The crescent is computed (outer arc of the moon + inner arc of the
// shadow between their intersections), sampled into points.
GlyphBase {
    id: g
    glyphName: "moon"

    property real pop: 0
    property real bite: 0
    property real rock: 0
    property real twinkle: 0
    property bool looping: false

    onBegin: popAnim.start()
    onPopChanged: if (!biteAnim.running && g.bite === 0 && g.pop >= g.p("biteAt", 0.6)) biteAnim.start()
    onBiteChanged: if (!g.looping && g.bite >= 1 - g.handoff) g.looping = true
    Spring { id: popAnim; target: g; property: "pop"; to: 1; stiffness: g.p("popStiffness", 7); damp: g.p("popDamping", 0.45); eps: 0.002 }
    Spring { id: biteAnim; target: g; property: "bite"; to: 1; stiffness: g.p("revealStiffness", 6); damp: 1; eps: 0.002 }
    SequentialAnimation on rock {
        running: g.looping
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: g.p("rockMs", 1300); easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: -1; duration: g.p("rockMs", 1300) * 2; easing.type: Easing.InOutSine }
        NumberAnimation { from: -1; to: 0; duration: g.p("rockMs", 1300); easing.type: Easing.InOutSine }
    }
    NumberAnimation on twinkle {
        running: g.looping
        from: 0
        to: 1
        duration: g.p("twinkleMs", 1600)
        loops: Animation.Infinite
    }

    readonly property var crescent: {
        const R = g.u(0.47), R2 = g.u(0.38);
        const c1 = [g.u(0.5), g.u(0.5)];
        const off = 1 + 1.7 * (1 - Math.min(1, Math.max(0, g.bite)));
        const c2 = [c1[0] + g.u(0.28) * off, c1[1] - g.u(0.23) * off];
        const d = Math.hypot(c2[0] - c1[0], c2[1] - c1[1]);
        if (d >= R + R2 - 0.01)
            return G.arcPts(c1[0], c1[1], R, 0, 360, 48);
        const th = Math.atan2(c2[1] - c1[1], c2[0] - c1[0]) * 180 / Math.PI;
        const al = Math.acos(G.clamp((R * R + d * d - R2 * R2) / (2 * R * d), -1, 1)) * 180 / Math.PI;
        // Outer arc: the long way round the moon, away from the shadow.
        const outer = G.arcPts(c1[0], c1[1], R, th + al, th + 360 - al, 40);
        // Inner arc: along the shadow between the two intersections, on
        // its side facing the moon's centre (through th + 180).
        const p2 = outer[outer.length - 1], p1 = outer[0];
        let a2 = Math.atan2(p2[1] - c2[1], p2[0] - c2[0]) * 180 / Math.PI;
        let a1 = Math.atan2(p1[1] - c2[1], p1[0] - c2[0]) * 180 / Math.PI;
        while (a1 < a2)
            a1 += 360;
        const mid = th + 180;
        const passes = ((mid - a2) % 360 + 360) % 360 <= a1 - a2;
        const inner = passes ? G.arcPts(c2[0], c2[1], R2, a2, a1, 24) : G.arcPts(c2[0], c2[1], R2, a2, a1 - 360, 24);
        return outer.concat(inner.slice(1, -1));
    }

    Item {
        anchors.fill: parent
        opacity: G.smooth(g.pop * 2.5)
        transform: [
            Scale { origin.x: g.u(0.5); origin.y: g.u(0.5); xScale: 0.3 + 0.7 * g.pop; yScale: 0.3 + 0.7 * g.pop },
            Rotation { origin.x: g.u(0.5); origin.y: g.u(0.5); angle: g.p("rockDeg", 5) * g.rock }
        ]
        GlyphFill {
            path: G.svg(g.crescent, true)
            colorTop: g.fillTop; colorBottom: g.fillBottom
            gy1: g.u(0.03); gy2: g.u(0.97)
            sheen: g.sheen
        }
    }
    // Stars in the bite, twinkling one after another.
    Repeater {
        model: [[0.8, 0.22, 0.075], [0.9, 0.44, 0.05], [0.64, 0.1, 0.045]]
        delegate: GlyphFill {
            id: star
            required property var modelData
            required property int index
            readonly property real t: (g.twinkle + star.index / 3) % 1
            readonly property real k: Math.sin(Math.PI * star.t) * (g.looping ? 1 : 0)
            readonly property real cx: g.u(star.modelData[0])
            readonly property real cy: g.u(star.modelData[1])
            readonly property real r: g.u(star.modelData[2]) * (0.4 + 0.6 * star.k)
            opacity: star.k
            path: `M ${cx} ${cy - r} Q ${cx} ${cy} ${cx + r} ${cy} Q ${cx} ${cy} ${cx} ${cy + r}`
                + ` Q ${cx} ${cy} ${cx - r} ${cy} Q ${cx} ${cy} ${cx} ${cy - r} Z`
            colorTop: g.deviceTop; colorBottom: g.fillTop
        }
    }
}
