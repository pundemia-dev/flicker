.pragma library

// Knockout holes for the frosted island (iOS 18 Control Center look):
// the backdrop tint is painted only BETWEEN the buttons, the buttons sit
// straight on the compositor blur. A hole = { x, y, w, h, r: [tl, tr, br, bl] }.
// The tint is one even-odd path (island outline + holes), so holes must
// not overlap each other (modules drop lifted / faded items).
// Optional `cut`: px cut off the top (a plate behind the card above): the
// hole is only the part below y + cut, its corners keep the full rect's
// arcs (a short strip would otherwise get radii clamped to half its height).

function hole(x, y, w, h, r, cut) {
    return { x: x, y: y, w: w, h: h, r: Array.isArray(r) ? r : [r, r, r, r], cut: cut ?? 0 };
}

// Maps a hole given in `item` coords into `target` coords (scale-aware:
// both corners are mapped, radii follow the horizontal scale).
function mapped(item, target, k) {
    const p0 = item.mapToItem(target, k.x, k.y);
    const p1 = item.mapToItem(target, k.x + k.w, k.y + k.h);
    const s = k.w > 0 ? (p1.x - p0.x) / k.w : 1;
    const sy = k.h > 0 ? (p1.y - p0.y) / k.h : 1;
    return hole(p0.x, p0.y, p1.x - p0.x, p1.y - p0.y, k.r.map(v => v * s), (k.cut ?? 0) * sy);
}

// Cuts a hole to an axis-aligned rect {x0, y0, x1, y1}; corners on a cut
// side shrink by the cut depth (approximation of the cut arc). null = gone.
function clipped(k, c) {
    // Cut hole: a top clip only deepens the cut; anything else falls back
    // to the plain visible rect.
    if (k.cut > 0) {
        const top = k.y + k.cut;
        if (k.x >= c.x0 && k.x + k.w <= c.x1 && k.y + k.h <= c.y1) {
            const cut = Math.max(top, c.y0) - k.y;
            return k.h - cut < 0.5 ? null : hole(k.x, k.y, k.w, k.h, k.r, cut);
        }
        const tl = Math.max(0, k.r[0] - k.cut), tr = Math.max(0, k.r[1] - k.cut);
        return clipped(hole(k.x, top, k.w, k.h - k.cut, [tl, tr, k.r[2], k.r[3]]), c);
    }
    const x0 = Math.max(k.x, c.x0), y0 = Math.max(k.y, c.y0);
    const x1 = Math.min(k.x + k.w, c.x1), y1 = Math.min(k.y + k.h, c.y1);
    if (x1 - x0 < 0.5 || y1 - y0 < 0.5)
        return null;
    const dl = x0 - k.x, dt = y0 - k.y, dr = k.x + k.w - x1, db = k.y + k.h - y1;
    if (dl + dt + dr + db === 0)
        return k;
    const cut = (r, a, b) => Math.max(0, r - Math.max(a, b));
    return hole(x0, y0, x1 - x0, y1 - y0, [cut(k.r[0], dt, dl), cut(k.r[1], dt, dr), cut(k.r[2], db, dr), cut(k.r[3], db, dl)]);
}

// Keeps a hole inside the rounded island outline (w x h, radius R): clipped
// to the box, and a corner sitting in an island corner zone is rounded at
// least as much as the outline there (concentric at equal insets), so the
// even-odd fill never paints tint outside the island's rounding while it
// morphs.
function insideOutline(k, w, h, R) {
    const c = clipped(k, { x0: 0, y0: 0, x1: w, y1: h });
    if (!c)
        return null;
    const need = (dx, dy) => dx < R && dy < R ? R - Math.min(dx, dy) : 0;
    const L = c.x, T = c.y + (c.cut ?? 0), Rt = w - (c.x + c.w), B = h - (c.y + c.h);
    return hole(c.x, c.y, c.w, c.h, [
        Math.max(c.r[0], need(L, T)), Math.max(c.r[1], need(Rt, T)),
        Math.max(c.r[2], need(Rt, B)), Math.max(c.r[3], need(L, B))], c.cut ?? 0);
}

function n(v) {
    return Math.round(v * 100) / 100;
}

// SVG subpath of a rounded rect with per-corner radii (clockwise).
function rectPath(k) {
    const m = Math.min(k.w, k.h) / 2;
    const [tl, tr, br, bl] = k.r.map(v => Math.max(0, Math.min(v, m)));
    const x = k.x, y = k.y, x1 = k.x + k.w, y1 = k.y + k.h;
    const arc = (r, ex, ey) => r > 0 ? ` A ${n(r)} ${n(r)} 0 0 1 ${n(ex)} ${n(ey)}` : ` L ${n(ex)} ${n(ey)}`;
    if (k.cut > 0)
        return cutPath(k, x, y, x1, y1, tl, tr, br, bl, arc);
    return `M ${n(x + tl)} ${n(y)} H ${n(x1 - tr)}` + arc(tr, x1, y + tr)
        + ` V ${n(y1 - br)}` + arc(br, x1 - br, y1)
        + ` H ${n(x + bl)}` + arc(bl, x, y1 - bl)
        + ` V ${n(y + tl)}` + arc(tl, x + tl, y) + " Z";
}

// Rounded rect below y + cut: the top edge starts where the cut line meets
// the side (inside a corner arc if it crosses one), arcs stay concentric.
function cutPath(k, x, y, x1, y1, tl, tr, br, bl, arc) {
    const y0 = y + Math.min(k.cut, k.h);
    const inset = (rt, rb) => {
        if (y0 < y + rt)
            return rt - Math.sqrt(Math.max(0, rt * rt - (y + rt - y0) ** 2));
        if (y0 > y1 - rb)
            return rb - Math.sqrt(Math.max(0, rb * rb - (y0 - y1 + rb) ** 2));
        return 0;
    };
    const ol = inset(tl, bl), or = inset(tr, br);
    let p = `M ${n(x + ol)} ${n(y0)} H ${n(x1 - or)}`;
    if (y0 < y + tr)
        p += arc(tr, x1, y + tr);
    if (y0 <= y1 - br)
        p += ` V ${n(y1 - br)}`;
    p += arc(br, x1 - br, y1) + ` H ${n(x + bl)}`;
    if (y0 > y1 - bl)
        return p + arc(bl, x + ol, y0) + " Z";
    p += arc(bl, x, y1 - bl);
    if (y0 < y + tl)
        return p + ` V ${n(y + tl)}` + arc(tl, x + ol, y0) + " Z";
    return p + ` V ${n(y0)} Z`;
}

function holesPath(holes) {
    return holes.map(rectPath).join(" ");
}
