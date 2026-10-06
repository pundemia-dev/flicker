.pragma library

// Wallpaper carousel geometry as a function of a card's offset `d` from the
// (animated) centre position, in cards. c = config.launcher.wallpapers.
// Tiers by distance: cardWidths[k] / cardHeights[k] (height as a factor of
// cardHeight) for |d| = k — the centre card is the largest, each step out
// a bit lower and narrower; past the last tier the last one repeats.
// Between tiers size interpolates linearly and x advances by
// (w[k] + w[k+1]) / 2 + cardSpacing per card, which keeps the gap between
// neighbours exactly cardSpacing at any d.

function tier(list, k) {
    return list[Math.min(k, list.length - 1)];
}

// Value of a tier list at |d| (linear between tiers).
function lerpTier(list, d) {
    const a = Math.abs(d);
    const k = Math.floor(a);
    const t = a - k;
    return tier(list, k) + (tier(list, k + 1) - tier(list, k)) * t;
}

function near(d) {
    return Math.min(Math.abs(d), 1);
}

function width(c, d) {
    return lerpTier(c.cardWidths, d);
}

function height(c, d) {
    return c.cardHeight * lerpTier(c.cardHeights, d);
}

// Distance between the centres of cards k and k+1.
function stepAt(c, k) {
    return (tier(c.cardWidths, k) + tier(c.cardWidths, k + 1)) / 2 + c.cardSpacing;
}

// Centre x of the card relative to the carousel centre.
function x(c, d) {
    const a = Math.abs(d);
    const k = Math.floor(a);
    let s = 0;
    for (let i = 0; i < k; i++)
        s += stepAt(c, i);
    return Math.sign(d) * (s + (a - k) * stepAt(c, k));
}

// Carousel width: exactly visibleCards cards at rest, edge to edge.
function bodyWidth(c) {
    const side = Math.floor((Math.max(1, c.visibleCards || 5) - 1) / 2);
    return 2 * (x(c, side) + tier(c.cardWidths, side) / 2);
}

// Art width: the widest card plus the parallax travel on both sides, so the
// shifted art always covers the card.
function artWidth(c) {
    return c.cardWidths[0] + 2 * c.parallax;
}

// Art offset inside the card (parallax): the art lags behind the card by
// `parallax` px per step, clamped where it would uncover a card edge.
function artShift(c, d) {
    if (c.parallax <= 0)
        return 0;
    const margin = (artWidth(c) - width(c, d)) / 2;
    return -Math.max(-margin, Math.min(margin, d * c.parallax));
}

// Fade towards the carousel edges: a card whose outer edge passes
// halfWidth - edgeFadeWidth starts to fade, gone at the edge.
function edgeOpacity(c, d, halfWidth) {
    const outer = Math.abs(x(c, d)) + width(c, d) / 2;
    const f = Math.max(1, c.edgeFadeWidth);
    return Math.max(0, Math.min(1, (halfWidth - outer + f) / f));
}

// Cards to keep alive either side of the centre: everything that can reach
// the visible width, +1 for the one sliding in.
function reach(c, halfWidth) {
    let k = 0;
    while (k < 64 && x(c, k) - tier(c.cardWidths, k) / 2 < halfWidth)
        k++;
    return k + 1;
}
