.pragma library

// Dashboard island rect from the grid metrics (Config.dashboard) and the
// layout's row count (services/DashboardLayout), so the grid and the island
// can never drift apart. Corner radius is concentric: island radius = card
// radius + margins.
//
// m = Config.dashboard (see DashboardModule layout):
// W = 2*margins + cols*unit + (cols-1)*spacing,
// H = 2*margins + header + spacing + grid + (editing ? spacing + footer : 0),
// grid = rows*unit + (rows-1)*spacing; edit mode adds one empty drop row and
// the footer (hidden-card chips | "Done", m.edit).

// m.edit with defaults: config.json replaces the whole dashboard group, so
// a file written before the edit keys existed has none.
function edit(m) {
    const e = m.edit ?? {};
    return {
        chipSize: e.chipSize ?? 34,
        chipSpacing: e.chipSpacing ?? 8,
        doneWidth: e.doneWidth ?? 84,
        titleSize: e.titleSize ?? 13,
        subtitleSize: e.subtitleSize ?? 11,
        holdMs: e.holdMs ?? 450,
        rimWidth: e.rimWidth ?? 3,
        rimBlinkMs: e.rimBlinkMs ?? 700,
        arcWidth: e.arcWidth ?? 8,
        arcCurve: e.arcCurve ?? 0.6,
        spacing: m.spacing
    };
}

function innerWidth(m) {
    const cols = m.cols || 8;
    return cols * m.unit + (cols - 1) * m.spacing;
}

function gridRows(rows, editing) {
    return Math.max(1, rows + (editing ? 1 : 0));
}

function gridHeight(m, rows, editing) {
    const r = gridRows(rows, editing);
    return r * m.unit + (r - 1) * m.spacing;
}

function chipsPerRow(m) {
    const e = edit(m);
    const room = innerWidth(m) - e.doneWidth - m.spacing;
    return Math.max(1, Math.floor((room + e.chipSpacing) / (e.chipSize + e.chipSpacing)));
}

function footerHeight(m, hiddenCount) {
    const e = edit(m);
    const rows = Math.max(1, Math.ceil(hiddenCount / chipsPerRow(m)));
    return rows * e.chipSize + (rows - 1) * e.chipSpacing;
}

function islandSize(m, rows, editing, hiddenCount) {
    return {
        width: 2 * m.margins + innerWidth(m),
        height: 2 * m.margins + m.headerHeight + m.spacing + gridHeight(m, rows, editing)
            + (editing ? m.spacing + footerHeight(m, hiddenCount) : 0),
        radius: m.cardRadius + m.margins
    };
}
