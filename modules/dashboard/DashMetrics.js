.pragma library

// Single source of the dashboard's pixel metrics. Config.dashboard holds
// base sizes (designed at scale 1); `scale` multiplies every size key, and
// cards multiply their own literal px by `k`. Island sizes the module from
// the same numbers, so the grid and the island can never drift apart.
// Corner radius is concentric: island radius = card radius + margins.

const SIZE_KEYS = ["unit", "headerHeight", "cardRadius", "spacing", "margins",
    "cardPadding", "titleSize", "dotSize", "valueSize", "bigValueSize",
    "headerTimeSize", "headerDateSize", "iconSize"];
const ROWS = 3;

function scaled(cfg) {
    const k = (cfg && cfg.scale) || 1;
    const out = Object.assign({}, cfg || {});
    out.k = k;
    for (const key of SIZE_KEYS) {
        if (typeof out[key] === "number")
            out[key] = Math.round(out[key] * k);
    }
    return out;
}

// Island rect for the scaled metrics m (see DashboardModule layout):
// W = 2*margins + cols*unit + (cols-1)*spacing,
// H = 2*margins + header + spacing + ROWS*unit + (ROWS-1)*spacing.
function islandSize(m) {
    const cols = m.cols || 8;
    return {
        width: 2 * m.margins + cols * m.unit + (cols - 1) * m.spacing,
        height: 2 * m.margins + m.headerHeight + m.spacing + ROWS * m.unit + (ROWS - 1) * m.spacing,
        radius: m.cardRadius + m.margins
    };
}
