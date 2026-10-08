.pragma library

// Path helpers for the drawn event glyphs (indicators/glyphs/*Glyph.qml).
// Everything works in pixels; glyphs pass `u(x)` = x * size. Paths are SVG
// strings for PathSvg (CurveRenderer); point lists are [[x, y], ...].

function clamp(v, lo, hi) {
    return Math.max(lo, Math.min(hi, v));
}

function smooth(t) {
    t = clamp(t, 0, 1);
    return t * t * (3 - 2 * t);
}

// Progress of `t` inside [a, b] (0 before, 1 after) — staggers phases off
// one driver.
function span(t, a, b) {
    return clamp((t - a) / Math.max(1e-6, b - a), 0, 1);
}

function svg(pts, closed) {
    if (!pts || pts.length === 0)
        return "";
    let p = `M ${pts[0][0]} ${pts[0][1]}`;
    for (let i = 1; i < pts.length; i++)
        p += ` L ${pts[i][0]} ${pts[i][1]}`;
    return closed ? p + " Z" : p;
}

function rrect(x, y, w, h, r) {
    r = Math.max(0, Math.min(r, w / 2, h / 2));
    return `M ${x + r} ${y} L ${x + w - r} ${y} A ${r} ${r} 0 0 1 ${x + w} ${y + r}`
        + ` L ${x + w} ${y + h - r} A ${r} ${r} 0 0 1 ${x + w - r} ${y + h}`
        + ` L ${x + r} ${y + h} A ${r} ${r} 0 0 1 ${x} ${y + h - r}`
        + ` L ${x} ${y + r} A ${r} ${r} 0 0 1 ${x + r} ${y} Z`;
}

function ellipse(cx, cy, rx, ry) {
    if (rx <= 0 || ry <= 0)
        return "";
    return `M ${cx - rx} ${cy} A ${rx} ${ry} 0 1 1 ${cx + rx} ${cy} A ${rx} ${ry} 0 1 1 ${cx - rx} ${cy} Z`;
}

function circle(cx, cy, r) {
    return ellipse(cx, cy, r, r);
}

// Points on a circle from angle a0 to a1 (degrees, clockwise from 3
// o'clock, y down), `n` segments.
function arcPts(cx, cy, r, a0, a1, n) {
    const out = [];
    n = Math.max(1, n || 16);
    for (let i = 0; i <= n; i++) {
        const a = (a0 + (a1 - a0) * i / n) * Math.PI / 180;
        out.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]);
    }
    return out;
}

// Rounded rectangle outline as points, clockwise from the top centre (a
// drawable perimeter for trim()).
function rrectPts(x, y, w, h, r, seg) {
    r = Math.max(0, Math.min(r, w / 2, h / 2));
    seg = seg || 6;
    let pts = [[x + w / 2, y], [x + w - r, y]];
    pts = pts.concat(arcPts(x + w - r, y + r, r, -90, 0, seg).slice(1));
    pts.push([x + w, y + h - r]);
    pts = pts.concat(arcPts(x + w - r, y + h - r, r, 0, 90, seg).slice(1));
    pts.push([x + r, y + h]);
    pts = pts.concat(arcPts(x + r, y + h - r, r, 90, 180, seg).slice(1));
    pts.push([x, y + r]);
    pts = pts.concat(arcPts(x + r, y + r, r, 180, 270, seg).slice(1));
    pts.push([x + w / 2, y]);
    return pts;
}

// The first `f` (0..1) of a polyline, by length.
function trim(pts, f) {
    if (!pts || pts.length < 2)
        return pts || [];
    let total = 0;
    for (let k = 0; k + 1 < pts.length; k++)
        total += Math.hypot(pts[k + 1][0] - pts[k][0], pts[k + 1][1] - pts[k][1]);
    let left = total * clamp(f, 0.0005, 1);
    const out = [pts[0]];
    for (let k = 0; k + 1 < pts.length && left > 0; k++) {
        const a = pts[k], b = pts[k + 1], l = Math.hypot(b[0] - a[0], b[1] - a[1]);
        const t = Math.min(1, left / Math.max(1e-6, l));
        out.push([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]);
        left -= l;
    }
    return out;
}

// Polygon clipped by a horizontal front: keep y <= front (down = false
// keeps y >= front). Sutherland–Hodgman against one edge — fine for
// concave shapes.
function clipY(pts, front, keepAbove) {
    const keep = p => keepAbove ? p[1] <= front : p[1] >= front;
    const out = [];
    for (let i = 0; i < pts.length; i++) {
        const p = pts[i], q = pts[(i + 1) % pts.length];
        if (keep(p))
            out.push(p);
        if (keep(p) !== keep(q)) {
            const t = (front - p[1]) / (q[1] - p[1]);
            out.push([p[0] + (q[0] - p[0]) * t, front]);
        }
    }
    return out.length >= 3 ? out : [];
}

function scalePts(pts, ox, oy, sx, sy) {
    return pts.map(p => [ox + (p[0] - ox) * sx, oy + (p[1] - oy) * sy]);
}

function movePts(pts, dx, dy) {
    return pts.map(p => [p[0] + dx, p[1] + dy]);
}

function rotatePts(pts, cx, cy, deg) {
    const r = deg * Math.PI / 180, c = Math.cos(r), sn = Math.sin(r);
    return pts.map(p => [cx + (p[0] - cx) * c - (p[1] - cy) * sn, cy + (p[0] - cx) * sn + (p[1] - cy) * c]);
}

// Ellipse as points, its x axis rotated by `deg` (clockwise, y down).
function ellipsePts(cx, cy, rx, ry, deg, n) {
    n = n || 40;
    const out = [];
    for (let i = 0; i < n; i++) {
        const a = 2 * Math.PI * i / n;
        out.push([cx + rx * Math.cos(a), cy + ry * Math.sin(a)]);
    }
    return rotatePts(out, cx, cy, deg);
}

// Stadium (fully rounded capsule) of length `len` along `deg`.
function stadiumPts(cx, cy, len, thick, deg) {
    const pts = rrectPts(cx - len / 2, cy - thick / 2, len, thick, thick / 2, 8);
    return rotatePts(pts, cx, cy, deg);
}

// Superellipse |x/rx|^e + |y/ry|^e = 1 (e = 2: ellipse; larger = squarer,
// less rounding), x axis rotated by `deg`.
function superellipsePts(cx, cy, rx, ry, deg, e, n) {
    n = n || 64;
    const k = 2 / Math.max(0.5, e);
    const out = [];
    for (let i = 0; i < n; i++) {
        const a = 2 * Math.PI * i / n, c = Math.cos(a), s = Math.sin(a);
        out.push([cx + rx * Math.sign(c) * Math.pow(Math.abs(c), k), cy + ry * Math.sign(s) * Math.pow(Math.abs(s), k)]);
    }
    return rotatePts(out, cx, cy, deg);
}
