import QtQuick
import QtQuick.Shapes

// Progress drawn along a rounded rectangle's outline, clockwise from the
// top: a dim `track` + the remaining part (`progress` 1 → 0, anchored at
// the start, the spent part is eaten from the end). `gap` (px, centred on
// the top edge) opens the outline: it starts at the gap's right edge and
// ends at its left edge (timer module: a third of the island; 0 = a closed
// loop from the top centre).
// With radius = size / 2 on a square box it is a ring — the timer
// ring in the bar and the island-perimeter progress are the SAME item
// (shared element: the box and radius morph, the outline follows).
// The stroke runs lineWidth / 2 inside the box, `radius` is the box's.
// `reveal` 0..1 draws the progress in from the top centre (both ends).
Item {
    id: root
    property real radius: Math.min(width, height) / 2
    property real lineWidth: 3
    property real gap: 0
    property real progress: 1
    property real reveal: 1
    property color color: "#FF9F0A"
    property color trackColor: "#33FFFFFF"
    // Corner segments per quarter: more on bigger corners.
    readonly property int seg: Math.max(4, Math.min(16, Math.round(root.radius / 3)))

    function outline(): var {
        const i = root.lineWidth / 2;
        const w = Math.max(0, root.width - 2 * i), h = Math.max(0, root.height - 2 * i);
        const r = Math.max(0, Math.min(root.radius - i, w / 2, h / 2));
        const x = i, y = i;
        const g = Math.max(0, Math.min(root.gap, w - 2 * r)) / 2;
        const pts = [[x + w / 2 + g, y], [x + w - r, y]];
        const arc = (cx, cy, a0) => {
            for (let k = 1; k <= root.seg; k++) {
                const a = (a0 + 90 * k / root.seg) * Math.PI / 180;
                pts.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]);
            }
        };
        arc(x + w - r, y + r, -90);
        pts.push([x + w, y + h - r]);
        arc(x + w - r, y + h - r, 0);
        pts.push([x + r, y + h]);
        arc(x + r, y + h - r, 90);
        pts.push([x, y + r]);
        arc(x + r, y + r, 180);
        pts.push([x + w / 2 - g, y]);
        return pts;
    }
    // Part of a polyline between length fractions a..b.
    function range(pts: var, a: real, b: real): var {
        let total = 0;
        const len = [];
        for (let k = 0; k + 1 < pts.length; k++) {
            const l = Math.hypot(pts[k + 1][0] - pts[k][0], pts[k + 1][1] - pts[k][1]);
            len.push(l);
            total += l;
        }
        const from = total * Math.max(0, Math.min(1, a)), to = total * Math.max(0, Math.min(1, b));
        if (to - from < 0.01)
            return [];
        const out = [];
        let at = 0;
        for (let k = 0; k < len.length; k++) {
            const s = at, e = at + len[k];
            at = e;
            if (e < from || s > to)
                continue;
            const p = pts[k], q = pts[k + 1];
            const lerp = d => {
                const t = len[k] > 0 ? (d - s) / len[k] : 0;
                return [p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t];
            };
            if (out.length === 0)
                out.push(lerp(Math.max(s, from)));
            out.push(lerp(Math.min(e, to)));
        }
        return out;
    }
    function svg(pts: var, closed: bool): string {
        if (pts.length < 2)
            return "";
        let s = `M ${pts[0][0]} ${pts[0][1]}`;
        for (let k = 1; k < pts.length; k++)
            s += ` L ${pts[k][0]} ${pts[k][1]}`;
        return closed ? s + " Z" : s;
    }

    readonly property var pts: root.width > 0 && root.height > 0 ? root.outline() : []
    readonly property string trackPath: root.pts.length ? root.svg(root.pts, root.gap < 0.5) : ""
    // Remaining part from the start; the spent part is eaten from the end.
    // reveal grows it out of the start.
    readonly property string fillPath: {
        if (!root.pts.length || root.progress <= 0 || root.reveal <= 0)
            return "";
        const shown = root.progress * Math.max(0, Math.min(1, root.reveal));
        return root.svg(root.range(root.pts, 0, shown), false);
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.trackColor
            strokeWidth: root.lineWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.trackPath }
        }
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.lineWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.fillPath }
        }
    }
}
