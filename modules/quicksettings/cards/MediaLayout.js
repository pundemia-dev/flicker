.pragma library

// Media card geometry per footprint (cols x rows). Every element exists in
// every layout, so a resize MORPHS: the card springs each rect to its new
// target (cover shrinks/grows, transport buttons travel under the cover);
// elements a layout lacks report show:false and leave through FadeBlur at
// their new spot.
//
// Sizes are the player module's px (modules/player/PlayerModule: margin 16,
// title 14, lyrics/output button 42, transport box 50 / glyph 34 / skip
// triangle 14 / spacing 10, bar 8, times 12) times k = playerScale, so the
// 4x2 card IS the player layout at card scale. 4x4 / 4x6 add a system
// volume row (speaker · bar · speaker, iOS Now Playing) under the transport.
// There the transport row gains a like button (left of prev) and takes the
// output button (right of next, bare grey glyph — no disc); a small audio
// visualizer (`viz`) takes the output button's old spot.
//
// g = { w, h, cols, rows, k, unit, pad, radius (card) }

const P = { margin: 16, gap: 14, out: 42, box: 50, glyph: 34, tri: 14, rowGap: 10,
    transportGap: 6, bar: 8, barGap: 8, times: 12, title: 14, volIcon: 18, volGap: 10 };

function titleHeight(k) {
    return 2 * Math.round(P.title * k * 1.3) + 2 * k;
}
function progressHeight(k) {
    return (P.bar + P.barGap) * k + Math.round(P.times * k * 1.3);
}

// Three transport slots centred on (cx, cy); withPrev false = a two-button
// row (play + next), prev parked under play.
function row(cx, cy, box, gap, withPrev, withNext) {
    if (!withPrev && withNext) {
        const half = (box + gap) / 2;
        return {
            prev: { cx: cx - half, cy: cy, show: false },
            play: { cx: cx - half, cy: cy, show: true },
            next: { cx: cx + half, cy: cy, show: true }
        };
    }
    return {
        prev: { cx: withPrev ? cx - box - gap : cx, cy: cy, show: withPrev },
        play: { cx: cx, cy: cy, show: true },
        next: { cx: withNext ? cx + box + gap : cx, cy: cy, show: withNext }
    };
}

// 4x4 / 4x6 transport row: like · prev · play · next · output. Like and
// output sit at the content edges (E), the transport splits the span
// between them evenly; output loses its disc (bare grey glyph).
function fullRow(L, W, E, out, cy, box) {
    const lx = E + out / 2;
    const rx = W - E - out / 2;
    const step = (rx - lx) / 4;
    L.buttons = row(W / 2, cy, box, step - box, true, true);
    L.like = { cx: lx, cy: cy, show: true };
    L.out = { x: rx - out / 2, y: cy - out / 2, show: true, bare: true };
    L.sideScale = 1.3;  // like / bare output glyph scale
}

function layout(g) {
    const k = g.k;
    const W = g.w, H = g.h;
    const M = P.margin * k;
    const out = P.out * k;
    const tH = titleHeight(k);
    const pH = progressHeight(k);
    const volH = P.volIcon * k * 1.25;
    const key = `${g.cols}x${g.rows}`;
    let L = null;

    if (key === "1x1") {
        L = {
            cover: { x: 0, y: 0, s: W, r: W / 2, dim: true },
            title: { x: g.pad, y: H, w: W - 2 * g.pad, show: false },
            out: { x: W - out, y: 0, show: false },
            progress: { x: g.pad, y: H - pH, w: W - 2 * g.pad, show: false },
            box: W * 0.6, glyph: P.glyph * k, tri: P.tri * k,
            buttons: row(W / 2, H / 2, W * 0.6, 0, false, false)
        };
    } else if (g.rows === 1) {
        // 2x1: cover disc + play/next; 4x1: + title and prev.
        const s = H - 2 * g.pad;
        const box = H - 2 * g.pad - 8;
        const wide = g.cols >= 4;
        const rowW = wide ? 3 * box : 2 * box;
        const cx = W - g.pad - rowW / 2;
        L = {
            cover: { x: g.pad, y: g.pad, s: s, r: s / 2, dim: false },
            title: { x: g.pad + s + g.pad * 0.75, y: (H - tH) / 2, w: Math.max(0, W - g.pad - s - g.pad * 0.75 - rowW - g.pad), show: wide },
            out: { x: W - out - g.pad, y: (H - out) / 2, show: false },
            progress: { x: g.pad, y: H - pH, w: W - 2 * g.pad, show: false },
            box: box, glyph: P.glyph * k * 0.85, tri: P.tri * k * 0.85,
            buttons: row(cx, H / 2, box, 0, wide, true)
        };
    } else if (key === "2x2") {
        // iOS small Now Playing: cover top-left, output top-right, title
        // under the cover, transport along the bottom.
        const p = g.pad;
        const s = g.unit - 2 * p;
        const box = (W - 2 * p) / 3;
        L = {
            cover: { x: p, y: p, s: s, r: s * 0.25, dim: false },
            title: { x: p, y: p + s + 4, w: W - 2 * p, show: true },
            out: { x: W - p - out, y: p + (s - out) / 2, show: true },
            progress: { x: p, y: H - p - pH, w: W - 2 * p, show: false },
            box: box, glyph: P.glyph * k * 0.85, tri: P.tri * k * 0.9,
            buttons: row(W / 2, H - p - box / 2 + 4, box, 0, true, true)
        };
    } else if (g.rows === 2) {
        // 4x2 = PlayerModule: full-height cover left; title + output on top
        // of the info column, transport above the progress block at the bottom.
        const s = H - 2 * M;
        const x0 = M + s + P.gap * k;
        const iw = W - x0 - M;
        const pY = H - M - pH;
        const box = P.box * k;
        L = {
            cover: { x: M, y: M, s: s, r: Math.max(8, g.radius - M), dim: false },
            title: { x: x0, y: M, w: iw - out - P.rowGap * k, show: true },
            out: { x: W - M - out, y: M + (tH - out) / 2, show: true },
            progress: { x: x0, y: pY, w: iw, show: true },
            box: box, glyph: P.glyph * k, tri: P.tri * k,
            buttons: row(x0 + iw / 2, pY - P.transportGap * k - box / 2, box, P.rowGap * k, true, true)
        };
    } else if (g.rows <= g.cols) {
        // 4x4: cover (half height) top-left, title beside it, output at the
        // cover's bottom-right; progress across, big transport, volume row
        // along the bottom. Edge inset E = twice the 4x2 margin (user).
        const E = 2 * M;
        const s = H / 2 - E;
        const x0 = E + s + P.gap * k;
        const pY = E + s + P.gap * k * 1.5;
        const box = P.box * k * 1.2;
        const vY = H - E - volH;
        const cy = (pY + pH + vY) / 2;
        L = {
            cover: { x: E, y: E, s: s, r: Math.max(8, g.radius - E), dim: false },
            title: { x: x0, y: E, w: W - x0 - E, show: true },
            viz: { x: W - E - out, y: E + s - out, show: true },
            progress: { x: E, y: pY, w: W - 2 * E, show: true },
            volume: { x: E, y: vY, w: W - 2 * E, show: true },
            // Glyphs grow, the hover disc (box) stays: the row is tight in 4x6.
            box: box, glyph: P.glyph * k * 1.4, tri: P.tri * k * 1.4
        };
        fullRow(L, W, E, out, cy, box);
    } else {
        // 4x6 (portrait): full-width cover, title + output under it,
        // progress, big transport, volume row along the bottom. Edge inset
        // E = twice the 4x2 margin (user).
        const E = 2 * M;
        const s = W - 2 * E;
        const tY = E + s + P.gap * k;
        const pY = tY + tH + P.gap * k;
        const box = P.box * k * 1.2;
        const vY = H - E - volH;
        const cy = (pY + pH + vY) / 2;
        L = {
            cover: { x: E, y: E, s: s, r: Math.max(8, g.radius - E), dim: false },
            title: { x: E, y: tY, w: W - 2 * E - out - P.rowGap * k, show: true },
            viz: { x: W - E - out, y: tY + (tH - out) / 2, show: true },
            progress: { x: E, y: pY, w: W - 2 * E, show: true },
            volume: { x: E, y: vY, w: W - 2 * E, show: true },
            // Glyphs grow, the hover disc (box) stays: the row is tight in 4x6.
            box: box, glyph: P.glyph * k * 1.4, tri: P.tri * k * 1.4
        };
        fullRow(L, W, E, out, cy, box);
    }
    // Layouts without the volume row park it at the bottom (hidden), so it
    // blur-fades in place when the card grows into 4x4 / 4x6.
    if (!L.volume)
        L.volume = { x: L.progress.x, y: H - M - volH, w: L.progress.w, show: false };
    // Like parks on prev, the visualizer on the output button (hidden):
    // both blur-fade in place when the card grows into 4x4 / 4x6.
    if (!L.like)
        L.like = { cx: L.buttons.prev.cx, cy: L.buttons.prev.cy, show: false };
    if (!L.viz)
        L.viz = { x: L.out.x, y: L.out.y, show: false };
    L.out.bare = L.out.bare ?? false;
    L.sideScale = L.sideScale ?? 1;
    L.volH = volH;
    L.volIcon = P.volIcon * k;
    L.volGap = P.volGap * k;
    L.outSize = out;
    L.titleSize = P.title * k;
    L.timesSize = P.times * k;
    L.bar = P.bar * k;
    L.barGap = P.barGap * k;
    return L;
}
