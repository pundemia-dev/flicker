.pragma library

// Quick Settings island rect from the grid metrics (Config.quicksettings),
// so grid and island never drift apart. Radius is concentric with the
// cards (card radius = unit/2): margins + unit/2.
//
// m = Config.quicksettings, rows = tallest page's rows, editing adds one
// empty drop row + the footer (hidden-card chips | "Готово"), railIcons =
// the tab rail right of the grid (several pages, or edit mode).

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

// railIcons = icons on the rail (pages, + the "+" in edit mode), 0 = no
// tabs. The session button (top-right corner, same column) keeps the
// column even without tabs.
function railWidth(m, railIcons) {
    return railIcons > 0 || m.sessionButton ? m.spacing + m.railWidth : 0;
}
// Session button top (island coords): where the island's right edge stops
// curving (y = island radius), so it sits in the straight part.
function sessionTop(m) {
    return m.margins + m.unit / 2;
}
// Its slot from the body top (button + gap); the tab icons stay centred,
// so the slot is reserved at the bottom too.
function sessionSlot(m) {
    return m.sessionButton ? sessionTop(m) - m.margins + m.sessionButtonSize + m.railSpacing : 0;
}
function railHeight(m, railIcons) {
    const icons = railIcons * m.railIcon + Math.max(0, railIcons - 1) * m.railSpacing;
    return icons > 0 ? icons + 2 * sessionSlot(m) : sessionSlot(m);
}

function viewportHeight(m, rows, editing) {
    const r = gridRows(rows, editing);
    return r * m.unit + (r - 1) * m.spacing;
}

function islandSize(m, rows, editing, hiddenCount, railIcons) {
    return {
        width: 2 * m.margins + innerWidth(m) + railWidth(m, railIcons),
        height: 2 * m.margins + Math.max(viewportHeight(m, rows, editing), railHeight(m, railIcons))
            + (editing ? m.spacing + footerHeight(m, hiddenCount) : 0),
        radius: m.margins + m.unit / 2
    };
}
