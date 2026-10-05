.pragma library

// Quick Settings island rect from the grid metrics (Config.quicksettings),
// so grid and island never drift apart. Radius is concentric with the
// cards (card radius = unit/2): margins + unit/2.
//
// m = Config.quicksettings, rows = layout rows, editing adds one empty
// drop row + the footer (hidden-card chips | "Готово").

function innerWidth(m) {
    return m.cols * m.unit + (m.cols - 1) * m.spacing;
}

function chipsPerRow(m) {
    const room = innerWidth(m) - m.doneWidth - m.spacing;
    return Math.max(1, Math.floor((room + m.chipSpacing) / (m.chipSize + m.chipSpacing)));
}

function footerHeight(m, hiddenCount) {
    const rows = Math.max(1, Math.ceil(hiddenCount / chipsPerRow(m)));
    return rows * m.chipSize + (rows - 1) * m.chipSpacing;
}

function gridRows(rows, editing) {
    return Math.max(1, rows + (editing ? 1 : 0));
}

function islandSize(m, rows, editing, hiddenCount) {
    const r = gridRows(rows, editing);
    return {
        width: 2 * m.margins + innerWidth(m),
        height: 2 * m.margins + r * m.unit + (r - 1) * m.spacing
            + (editing ? m.spacing + footerHeight(m, hiddenCount) : 0),
        radius: m.margins + m.unit / 2
    };
}
