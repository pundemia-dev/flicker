.pragma library

// Metaball neck between two circles (Hiroyuki Sato's construction, as in
// varun.ca/metaballs): the closed outline p1 → (bezier) → p3 → around the
// FAR side of circle 2 → p4 → (bezier) → p2 → back across circle 1.
// Circle 1 is the island's end rounding (painted over by the island), so
// only the neck and circle 2 show. `spread` 0..1 = how far round the
// circles the neck grips (0 = a hairline on the centre line), `handle` =
// bezier handle length. Below a spread of 0.15 the neck is gone (a thinner one
// renders as a dotted hairline). Returns an SVG path ("" = no neck).

function vec(c, a, r) {
    return [c[0] + r * Math.cos(a), c[1] + r * Math.sin(a)];
}

function dist(a, b) {
    return Math.hypot(b[0] - a[0], b[1] - a[1]);
}

function neck(c1, r1, c2, r2, spread, handle) {
    const d = dist(c1, c2);
    if (r1 <= 0 || r2 <= 0 || d <= Math.abs(r1 - r2) + 0.01 || spread <= 0.15)
        return "";
    let u1 = 0, u2 = 0;
    if (d < r1 + r2) {
        u1 = Math.acos(Math.max(-1, Math.min(1, (r1 * r1 + d * d - r2 * r2) / (2 * r1 * d))));
        u2 = Math.acos(Math.max(-1, Math.min(1, (r2 * r2 + d * d - r1 * r1) / (2 * r2 * d))));
    }
    const between = Math.atan2(c2[1] - c1[1], c2[0] - c1[0]);
    const maxSpread = Math.acos(Math.max(-1, Math.min(1, (r1 - r2) / d)));
    const v = spread;
    const a1 = between + u1 + (maxSpread - u1) * v;
    const a2 = between - u1 - (maxSpread - u1) * v;
    const a3 = between + Math.PI - u2 - (Math.PI - u2 - maxSpread) * v;
    const a4 = between - Math.PI + u2 + (Math.PI - u2 - maxSpread) * v;
    const p1 = vec(c1, a1, r1), p2 = vec(c1, a2, r1);
    const p3 = vec(c2, a3, r2), p4 = vec(c2, a4, r2);
    const total = r1 + r2;
    const d2 = Math.min(v * handle, dist(p1, p3) / total) * Math.min(1, d * 2 / total);
    const h1 = vec(p1, a1 - Math.PI / 2, r1 * d2);
    const h2 = vec(p2, a2 + Math.PI / 2, r1 * d2);
    const h3 = vec(p3, a3 + Math.PI / 2, r2 * d2);
    const h4 = vec(p4, a4 - Math.PI / 2, r2 * d2);
    const f = p => `${p[0].toFixed(2)} ${p[1].toFixed(2)}`;
    const large = d > r1 ? 1 : 0;
    return `M ${f(p1)} C ${f(h1)} ${f(h3)} ${f(p3)} A ${r2} ${r2} 0 ${large} 0 ${f(p4)} C ${f(h4)} ${f(h2)} ${f(p2)} Z`;
}

function smoothstep(a, b, x) {
    if (b <= a)
        return x >= b ? 1 : 0;
    const t = Math.max(0, Math.min(1, (x - a) / (b - a)));
    return t * t * (3 - 2 * t);
}
