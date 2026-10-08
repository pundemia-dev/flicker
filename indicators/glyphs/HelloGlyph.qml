import QtQuick
import "Glyph.js" as G

// "hello" in Apple's setup-screen style: the word is WRITTEN in one
// continuous cursive stroke (the line is trimmed along its length as if a
// pen moves), its colour flowing along the word through a hue range
// (Shape has no stroke gradients, so the stroke is cut into `segments`
// pieces, each in its own hue; round caps hide the joints). Meant for the
// first-run greeting, not an event slot: it is `aspect` × size wide.
// Timed writing (constant pen speed reads like handwriting, not a spring).
GlyphBase {
    id: g
    glyphName: "hello"

    property real write: 0
    readonly property real aspect: g.p("aspect", 2.4)
    width: g.size * g.aspect

    onBegin: writeAnim.start()
    NumberAnimation {
        id: writeAnim
        target: g
        property: "write"
        from: 0
        to: 1
        duration: g.p("writeMs", 2600)
        easing.type: Easing.InOutSine
    }

    // The word as cubic Béziers in an 82 × 34 box (baseline y 30).
    readonly property var curves: [
        [[2, 30], [8, 28], [14, 20], [16, 10]],
        [[16, 10], [17, 4], [14, 0], [12, 4]],
        [[12, 4], [10, 10], [10, 22], [10, 30]],
        [[10, 30], [12, 22], [16, 18], [19, 19]],
        [[19, 19], [22, 20], [21, 26], [22, 29]],
        [[22, 29], [23, 31], [27, 30], [30, 26]],
        [[30, 26], [33, 24], [38, 22], [37, 18]],
        [[37, 18], [36, 15], [31, 16], [30, 21]],
        [[30, 21], [29, 27], [33, 31], [38, 29]],
        [[38, 29], [42, 27], [45, 20], [47, 10]],
        [[47, 10], [48, 4], [45, 1], [44, 5]],
        [[44, 5], [42, 11], [42, 24], [44, 29]],
        [[44, 29], [46, 32], [50, 28], [53, 20]],
        [[53, 20], [55, 12], [57, 4], [54, 3]],
        [[54, 3], [51, 3], [51, 16], [52, 26]],
        [[52, 26], [53, 31], [58, 30], [61, 25]],
        [[61, 25], [63, 21], [64, 18], [68, 18]],
        [[68, 18], [72, 18], [73, 25], [70, 28]],
        [[70, 28], [67, 31], [62, 29], [63, 24]],
        [[63, 24], [64, 20], [69, 18], [73, 19]],
        [[73, 19], [76, 20], [78, 19], [80, 17]]
    ]
    // Sampled polyline fitted into the item (pixels), with cumulative lengths.
    readonly property var line: {
        const k = Math.min(g.width / 82, g.height / 34), ox = (g.width - 82 * k) / 2, oy = (g.height - 34 * k) / 2;
        const pts = [];
        for (const c of g.curves) {
            for (let i = pts.length ? 1 : 0; i <= 12; i++) {
                const t = i / 12, m = 1 - t;
                const x = m * m * m * c[0][0] + 3 * m * m * t * c[1][0] + 3 * m * t * t * c[2][0] + t * t * t * c[3][0];
                const y = m * m * m * c[0][1] + 3 * m * m * t * c[1][1] + 3 * m * t * t * c[2][1] + t * t * t * c[3][1];
                pts.push([ox + x * k, oy + y * k]);
            }
        }
        return pts;
    }
    readonly property int segments: g.p("segments", 28)
    // The polyline cut into `segments` equal-length pieces.
    readonly property var pieces: {
        const out = [];
        const n = g.segments;
        for (let s = 0; s < n; s++) {
            const a = G.trim(g.line, (s + 1) / n);
            const b = G.trim(g.line, s / n);
            // Piece = the part of `a` past the end of `b` (+ its last point).
            out.push([b[b.length - 1], ...a.slice(b.length - 1)]);
        }
        return out;
    }

    Repeater {
        model: g.segments
        delegate: GlyphLine {
            id: piece
            required property int index
            readonly property real local: G.clamp(g.write * g.segments - piece.index, 0, 1)
            path: piece.local > 0 ? G.svg(G.trim(g.pieces[piece.index] ?? [], piece.local), false) : ""
            color: Qt.hsla((g.p("hueStart", 0.55) + g.p("hueSpan", 0.55) * piece.index / g.segments) % 1, 0.85, 0.66, 1)
            lineWidth: g.u(g.p("stroke", 0.075))
        }
    }
}
