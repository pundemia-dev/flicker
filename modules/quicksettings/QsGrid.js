.pragma library

// Quick Settings layout engine (pure functions, no QML). A layout is an
// array of { id, x, y, w, h } in grid cells; columns are fixed (cols),
// rows grow as needed. Gaps are allowed (iOS Control Center keeps empty
// slots), only fully empty rows are squeezed out on commit.
//
// Placement model = "pin + push": the card being moved/resized is pinned
// at its target; every other card keeps its spot if still free, else it
// is displaced. A displaced card first tries the pinned card's vacated
// origin (so two equal cards SWAP, like iOS), then the first free slot
// scanning forward in reading order from its own spot.

function clone(items) {
    return items.map(i => ({ id: i.id, x: i.x, y: i.y, w: i.w, h: i.h }));
}

function overlaps(a, b) {
    return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
}

function fits(occupied, r, cols) {
    if (r.x < 0 || r.y < 0 || r.x + r.w > cols)
        return false;
    for (const o of occupied)
        if (overlaps(o, r))
            return false;
    return true;
}

// First free w x h slot at or after (fromX, fromY) in reading order.
// Always terminates: rows are unbounded.
function firstFree(occupied, w, h, cols, fromX, fromY) {
    for (let y = Math.max(0, fromY); ; y++) {
        for (let x = y === fromY ? Math.max(0, fromX) : 0; x + w <= cols; x++) {
            if (fits(occupied, { x: x, y: y, w: w, h: h }, cols))
                return { x: x, y: y };
        }
    }
}

function rowsOf(items) {
    let r = 0;
    for (const i of items)
        r = Math.max(r, i.y + i.h);
    return r;
}

// Re-resolve collisions around pinnedId (optional). origin = the pinned
// card's previous { x, y } (swap target), or null.
function resolve(items, cols, pinnedId, origin) {
    const out = clone(items);
    for (const i of out) {
        i.w = Math.min(i.w, cols);
        i.x = Math.max(0, Math.min(i.x, cols - i.w));
        i.y = Math.max(0, i.y);
    }
    const pinned = out.find(i => i.id === pinnedId) ?? null;
    const occupied = pinned ? [pinned] : [];
    const rest = out.filter(i => i !== pinned).sort((a, b) => a.y - b.y || a.x - b.x);
    for (const it of rest) {
        if (!fits(occupied, it, cols)) {
            const swap = origin ? { x: origin.x, y: origin.y, w: it.w, h: it.h } : null;
            const p = swap && fits(occupied, swap, cols) ? swap : firstFree(occupied, it.w, it.h, cols, it.x, it.y);
            it.x = p.x;
            it.y = p.y;
        }
        occupied.push(it);
    }
    return out;
}

// Drops rows no card touches (moving the last card off a row must not
// leave a hole in the island).
function squeeze(items) {
    const out = clone(items);
    const rows = rowsOf(out);
    for (let y = rows - 1; y >= 0; y--) {
        if (out.some(i => i.y <= y && y < i.y + i.h))
            continue;
        for (const i of out)
            if (i.y > y)
                i.y -= 1;
    }
    return out;
}

function moveTo(items, cols, id, x, y) {
    const src = items.find(i => i.id === id);
    if (!src)
        return clone(items);
    const moved = clone(items);
    const it = moved.find(i => i.id === id);
    it.x = x;
    it.y = y;
    return resolve(moved, cols, id, { x: src.x, y: src.y });
}

function resizeTo(items, cols, id, w, h) {
    const sized = clone(items);
    const it = sized.find(i => i.id === id);
    if (!it)
        return sized;
    it.w = w;
    it.h = h;
    return resolve(sized, cols, id, null);
}

function add(items, cols, id, w, h) {
    const out = clone(items).filter(i => i.id !== id);
    const p = firstFree(out, w, h, cols, 0, 0);
    out.push({ id: id, x: p.x, y: p.y, w: w, h: h });
    return out;
}

function remove(items, id) {
    return clone(items).filter(i => i.id !== id);
}

// The allowed size closest to the wanted (fractional) one, in cells.
function nearestSize(sizes, wantW, wantH) {
    let best = sizes[0];
    let bestD = Infinity;
    for (const s of sizes) {
        const d = (s[0] - wantW) * (s[0] - wantW) + (s[1] - wantH) * (s[1] - wantH);
        if (d < bestD) {
            bestD = d;
            best = s;
        }
    }
    return best;
}

function same(a, b) {
    if (a.length !== b.length)
        return false;
    for (const i of a) {
        const j = b.find(k => k.id === i.id);
        if (!j || j.x !== i.x || j.y !== i.y || j.w !== i.w || j.h !== i.h)
            return false;
    }
    return true;
}
