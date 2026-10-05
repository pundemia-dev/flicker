.pragma library

// Geometry of the shape-built volume icon (components/VolumeIcon.qml).
// Everything is a flattened polygon so the mute slash can CUT a sharp-edged
// gap through the speaker and the arcs (Qt Shapes have no boolean ops):
// polygon minus the slash's cut quad = Greiner–Hormann difference. The
// pieces never overlap — CurveRenderer drops overlaps of one path, and any
// overlap/shared edge between paths shows as a line on translucent ink.
//
// Design units first (relative sizes only), then everything is scaled so
// the tallest part spans exactly the icon height S (see normalize below).
// Speaker = rectangle rounded on the left + trapezoid (cone) on its right,
// its acute far corners rounded.

var BODY_W = 0.24;     // rectangle width
var BODY_H = 0.414;    // rectangle height (= cone's narrow side)
var BODY_R = 0.105;    // rectangle left corner radius
var CONE_W = 0.288;    // trapezoid width
var CONE_FIT = 0.95;   // cone height vs the biggest arc (fitted below)
var CONE_H = 0.86;     // trapezoid wide side (re-fitted below)
var CONE_R = 0.075;    // acute corner radius
var ARC_R0 = 0.24;     // first arc's centre-line radius
var SPEAKER_GAP = 0.19; // speaker -> first arc, at the closest point (arc ends)
var ARC_GAP = 0.17;    // clear space between neighbouring arcs
var ARC_SPAN = 45 * Math.PI / 180; // reference half-angle of the arcs
var HEIGHT_FIT = 0.8;  // arcs + cone height vs the reference (rectangle keeps its own)
var ARC_FIT = 1.05;    // arcs only, on top of HEIGHT_FIT (cone stays)
var ARC_LEN_FIT = [1.15, 1.075, 1]; // per-arc length (span) tweak: small arcs longer
var ARC_H_FIT = [1.1, 1, 1];  // per-arc height tweak on top (via span too)
var STROKE = 0.085;    // arc thickness = slash width
var GAP = 0.06;        // slash <-> icon gap
var SEG = 6;           // segments per rounded corner

var SPEAKER_RIGHT = BODY_W + CONE_W;
var ARC_R = [ARC_R0, ARC_R0 + ARC_GAP + STROKE, ARC_R0 + 2 * (ARC_GAP + STROKE)];
// Arc heights = HEIGHT_FIT x ARC_FIT x their reference height (span ARC_SPAN): each
// arc gets its own shorter span, so arcs stay circular and the radial
// spacing is untouched.
var ARC_SPANS = ARC_R.map(function (r, i) {
    var full = r * Math.sin(ARC_SPAN) + STROKE / 2;
    var span = Math.asin(Math.max(0, Math.min(1, (full * HEIGHT_FIT * ARC_FIT - STROKE / 2) / r)));
    span = Math.min(Math.PI / 2, span * ARC_LEN_FIT[i]);
    var hgt = (r * Math.sin(span) + STROKE / 2) * ARC_H_FIT[i];
    return Math.asin(Math.max(0, Math.min(1, (hgt - STROKE / 2) / r)));
});
// Common arc centre: placed so the first arc's ends (inner edge of the
// round caps) keep SPEAKER_GAP to the cone's right edge.
var ARC_CX = SPEAKER_RIGHT + SPEAKER_GAP + STROKE / 2 - ARC_R0 * Math.cos(ARC_SPANS[0]);
// Height of the drawn content (in S, set by normalize): the slash spans it.
var CONTENT_H = 1;

// Right edge of the content with arc i (0-based) as the last one.
function arcExtent(i) {
    return ARC_CX + ARC_R[i] + STROKE / 2;
}

// Content width (in S) for fractional arc visibilities vis[0..2]: every
// arc adds the space up to its outer edge, scaled by its visibility, so
// the speaker slides while an arc fades.
function contentWidth(vis, maxArcs) {
    var w = SPEAKER_RIGHT;
    var prev = SPEAKER_RIGHT;
    for (var i = 0; i < maxArcs; i++) {
        var e = arcExtent(i);
        w += (e - prev) * Math.max(0, Math.min(1, vis[i]));
        prev = e;
    }
    return w;
}

function roundPoly(vs, rs, seg) {
    var out = [];
    var n = vs.length;
    for (var i = 0; i < n; i++) {
        var V = vs[i], P = vs[(i + n - 1) % n], N = vs[(i + 1) % n];
        var r = rs[i];
        if (r <= 0) {
            out.push(V);
            continue;
        }
        var ax = P.x - V.x, ay = P.y - V.y, la = Math.hypot(ax, ay);
        var bx = N.x - V.x, by = N.y - V.y, lb = Math.hypot(bx, by);
        ax /= la; ay /= la; bx /= lb; by /= lb;
        var th = Math.acos(Math.max(-1, Math.min(1, ax * bx + ay * by)));
        var d = Math.min(r / Math.tan(th / 2), la / 2, lb / 2);
        var rr = d * Math.tan(th / 2);
        var mx = ax + bx, my = ay + by, lm = Math.hypot(mx, my);
        var oc = rr / Math.sin(th / 2);
        var ox = V.x + mx / lm * oc, oy = V.y + my / lm * oc;
        var a1 = Math.atan2(V.y + ay * d - oy, V.x + ax * d - ox);
        var a2 = Math.atan2(V.y + by * d - oy, V.x + bx * d - ox);
        var da = a2 - a1;
        while (da > Math.PI) da -= 2 * Math.PI;
        while (da < -Math.PI) da += 2 * Math.PI;
        for (var k = 0; k <= seg; k++) {
            var a = a1 + da * k / seg;
            out.push({ x: ox + rr * Math.cos(a), y: oy + rr * Math.sin(a) });
        }
    }
    return out;
}

function bodyPoly(S) {
    var yt = (0.5 - BODY_H / 2) * S, yb = (0.5 + BODY_H / 2) * S;
    var yT = (0.5 - CONE_H / 2) * S, yB = (0.5 + CONE_H / 2) * S;
    var bw = BODY_W * S, cr = SPEAKER_RIGHT * S;
    return roundPoly([
        { x: 0, y: yt }, { x: bw, y: yt }, { x: cr, y: yT },
        { x: cr, y: yB }, { x: bw, y: yb }, { x: 0, y: yb }
    ], [BODY_R * S, 0, CONE_R * S, CONE_R * S, 0, BODY_R * S], SEG);
}

// Cone height = CONE_FIT x the biggest arc's HEIGHT_FIT height (round caps
// included; ARC_FIT does not move the cone).
// Normalization uses the REFERENCE heights (before HEIGHT_FIT), so the
// shortened arcs/cone really are shorter in the box and the rectangle
// keeps its size; the content is then less than S tall (CONTENT_H).
// Fitted on the ROUNDED outline: the corner fillets drop the cone's top
// below its sharp vertex, so solve for the vertex height (a few passes —
// the drop depends a little on the cone's slant). Then normalize: scale
// every length so the tallest part spans exactly the icon height.
(function fitAndNormalize() {
    var refTop = ARC_R[2] * Math.sin(ARC_SPAN) + STROKE / 2;
    var arcTop = ARC_R[2] * Math.sin(ARC_SPANS[2]) + STROKE / 2;
    var top = refTop * HEIGHT_FIT * CONE_FIT;
    for (var k = 0; k < 4; k++) {
        var minY = 1;
        var poly = bodyPoly(1);
        for (var i = 0; i < poly.length; i++)
            minY = Math.min(minY, poly[i].y);
        var drop = minY - (0.5 - CONE_H / 2);
        CONE_H = 2 * (top + drop);
    }
    var n = 1 / (2 * Math.max(refTop, refTop * CONE_FIT, BODY_H / 2));
    CONTENT_H = 2 * Math.max(arcTop, top, BODY_H / 2) * n;
    BODY_W *= n; BODY_H *= n; BODY_R *= n;
    CONE_W *= n; CONE_H *= n; CONE_R *= n;
    STROKE *= n; GAP *= n; ARC_CX *= n;
    SPEAKER_RIGHT *= n;
    for (var j = 0; j < ARC_R.length; j++)
        ARC_R[j] *= n;
})();

// Annular sector with round caps (a thick arc as a fillable outline).
function arcPoly(S, i) {
    var sp = ARC_SPANS[i];
    var cx = ARC_CX * S, cy = S / 2, r = ARC_R[i] * S, h = STROKE * S / 2;
    var steps = 10 + 4 * i, capSteps = 8, out = [], k, a;
    for (k = 0; k <= steps; k++) {
        a = -sp + 2 * sp * k / steps;
        out.push({ x: cx + (r + h) * Math.cos(a), y: cy + (r + h) * Math.sin(a) });
    }
    var ex = cx + r * Math.cos(sp), ey = cy + r * Math.sin(sp);
    for (k = 1; k < capSteps; k++) {
        a = sp + Math.PI * k / capSteps;
        out.push({ x: ex + h * Math.cos(a), y: ey + h * Math.sin(a) });
    }
    for (k = 0; k <= steps; k++) {
        a = sp - 2 * sp * k / steps;
        out.push({ x: cx + (r - h) * Math.cos(a), y: cy + (r - h) * Math.sin(a) });
    }
    ex = cx + r * Math.cos(-sp);
    ey = cy + r * Math.sin(-sp);
    for (k = 1; k < capSteps; k++) {
        a = -sp + Math.PI + Math.PI * k / capSteps;
        out.push({ x: ex + h * Math.cos(a), y: ey + h * Math.sin(a) });
    }
    return out;
}

// Arcs scale about their common centre: a bump pushes the arc away from
// the speaker (wave = a ripple travelling outward).
function arcCenter(S) {
    return { x: ARC_CX * S, y: S / 2 };
}

function scaled(poly, o, s) {
    if (s === 1)
        return poly;
    return poly.map(function (p) {
        return { x: o.x + (p.x - o.x) * s, y: o.y + (p.y - o.y) * s };
    });
}

function inside(pt, poly) {
    var c = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
        var A = poly[i], B = poly[j];
        if ((A.y > pt.y) !== (B.y > pt.y)
                && pt.x < (B.x - A.x) * (pt.y - A.y) / (B.y - A.y) + A.x)
            c = !c;
    }
    return c;
}

// Greiner–Hormann P \ R (R convex, any orientation). Returns a list of
// polygons. Vertices landing exactly on an edge of R are not handled —
// R's corners are unrelated floats, so in practice they never do.
function difference(P, R) {
    var hits = [], i, j;
    var pe = P.map(function () { return []; });
    var re = R.map(function () { return []; });
    for (i = 0; i < P.length; i++) {
        var a = P[i], b = P[(i + 1) % P.length];
        for (j = 0; j < R.length; j++) {
            var c = R[j], d = R[(j + 1) % R.length];
            var den = (b.x - a.x) * (d.y - c.y) - (b.y - a.y) * (d.x - c.x);
            if (Math.abs(den) < 1e-12)
                continue;
            var t = ((c.x - a.x) * (d.y - c.y) - (c.y - a.y) * (d.x - c.x)) / den;
            var u = ((c.x - a.x) * (b.y - a.y) - (c.y - a.y) * (b.x - a.x)) / den;
            if (t <= 0 || t >= 1 || u <= 0 || u >= 1)
                continue;
            var x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t;
            var np = { x: x, y: y, inter: true, alpha: t };
            var nr = { x: x, y: y, inter: true, alpha: u };
            np.neighbor = nr;
            nr.neighbor = np;
            pe[i].push(np);
            re[j].push(nr);
            hits.push(np);
        }
    }
    if (hits.length === 0)
        return inside(P[0], R) ? [] : [P];

    function ring(src, edges) {
        var list = [];
        for (var k = 0; k < src.length; k++) {
            list.push({ x: src[k].x, y: src[k].y, inter: false });
            edges[k].sort(function (m, n) { return m.alpha - n.alpha; });
            for (var q = 0; q < edges[k].length; q++)
                list.push(edges[k][q]);
        }
        for (k = 0; k < list.length; k++) {
            list[k].next = list[(k + 1) % list.length];
            list[k].prev = list[(k + list.length - 1) % list.length];
        }
        return list;
    }
    var lp = ring(P, pe), lr = ring(R, re);
    // Difference: P's entry flags inverted (keep its outside runs, walk
    // forward), R's normal (walk its inside-P runs backward).
    var st = inside(P[0], R);
    for (i = 0; i < lp.length; i++)
        if (lp[i].inter) {
            lp[i].entry = st;
            st = !st;
        }
    st = inside(R[0], P);
    for (i = 0; i < lr.length; i++)
        if (lr[i].inter) {
            lr[i].entry = !st;
            st = !st;
        }

    var out = [];
    for (i = 0; i < hits.length; i++) {
        if (hits[i].visited)
            continue;
        var cur = hits[i], poly = [{ x: cur.x, y: cur.y }], guard = 0;
        do {
            cur.visited = true;
            cur.neighbor.visited = true;
            var fwd = cur.entry;
            do {
                cur = fwd ? cur.next : cur.prev;
                poly.push({ x: cur.x, y: cur.y });
            } while (!cur.inter && ++guard < 10000);
            cur = cur.neighbor;
        } while (!cur.visited && ++guard < 10000);
        poly.pop(); // closing point = the start
        if (poly.length >= 3)
            out.push(poly);
    }
    return out;
}

// Slash from the content's top-left to its bottom-right, inset so the round
// caps stay inside. A bare speaker is narrow (the slash would stand almost
// upright), so the slash box is at least SLASH_MIN_W wide, centred.
var SLASH_MIN_W = 0.8;

function slash(S, W) {
    var w = STROKE * S, ins = w * 0.5;
    var bw = Math.max(W, SLASH_MIN_W * S), x0 = (W - bw) / 2;
    var y0 = (1 - CONTENT_H) / 2 * S;
    var ax = x0 + ins, ay = y0 + ins, bx = x0 + bw - ins, by = S - y0 - ins;
    var len = Math.hypot(bx - ax, by - ay);
    return { ax: ax, ay: ay, bx: bx, by: by, len: len,
             dx: (bx - ax) / len, dy: (by - ay) / len, w: w };
}

// Polygon -> list of pieces (Qt.point lists) with the slash gap cut out:
// the cut quad = band |n| <= w/2 + gap from behind the start up to the
// drawn tip (+ w/2 + gap), so the gap grows together with the slash.
function cut(poly, sl, p, S) {
    var pieces = [poly];
    if (p > 0.001) {
        var h = sl.w / 2 + GAP * S;
        var nx = -sl.dy, ny = sl.dx;
        var t0 = -S, t1 = sl.len * p + h;
        function at(t, n) {
            return { x: sl.ax + sl.dx * t + nx * n, y: sl.ay + sl.dy * t + ny * n };
        }
        pieces = difference(poly, [at(t0, -h), at(t1, -h), at(t1, h), at(t0, h)]);
    }
    return pieces.map(function (pc) {
        return pc.map(function (q) {
            return Qt.point(q.x, q.y);
        });
    });
}
