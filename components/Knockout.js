.pragma library

// Knockout holes for the frosted island (iOS 18 Control Center look):
// the backdrop tint is painted only BETWEEN the buttons, the buttons sit
// straight on the compositor blur. A hole = { x, y, w, h, r: [tl, tr, br, bl] }.
// The tint is one even-odd path (island outline + holes), so holes must
// not overlap each other (modules drop lifted / faded items).

function hole(x, y, w, h, r) {
    return { x: x, y: y, w: w, h: h, r: Array.isArray(r) ? r : [r, r, r, r] };
}

// Maps a hole given in `item` coords into `target` coords (scale-aware:
// both corners are mapped, radii follow the horizontal scale).
function mapped(item, target, k) {
    const p0 = item.mapToItem(target, k.x, k.y);
    const p1 = item.mapToItem(target, k.x + k.w, k.y + k.h);
    const s = k.w > 0 ? (p1.x - p0.x) / k.w : 1;
    return hole(p0.x, p0.y, p1.x - p0.x, p1.y - p0.y, k.r.map(v => v * s));
}

// Cuts a hole to an axis-aligned rect {x0, y0, x1, y1}; corners on a cut
// side shrink by the cut depth (approximation of the cut arc). null = gone.
function clipped(k, c) {
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
    const L = c.x, T = c.y, Rt = w - (c.x + c.w), B = h - (c.y + c.h);
    return hole(c.x, c.y, c.w, c.h, [
        Math.max(c.r[0], need(L, T)), Math.max(c.r[1], need(Rt, T)),
        Math.max(c.r[2], need(Rt, B)), Math.max(c.r[3], need(L, B))]);
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
    return `M ${n(x + tl)} ${n(y)} H ${n(x1 - tr)}` + arc(tr, x1, y + tr)
        + ` V ${n(y1 - br)}` + arc(br, x1 - br, y1)
        + ` H ${n(x + bl)}` + arc(bl, x, y1 - bl)
        + ` V ${n(y + tl)}` + arc(tl, x + tl, y) + " Z";
}

function holesPath(holes) {
    return holes.map(rectPath).join(" ");
}
