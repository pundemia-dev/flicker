.pragma library

// Dashboard island rect from the grid metrics (Config.dashboard), so the
// grid and the island can never drift apart. Corner radius is concentric:
// island radius = card radius + margins.

const ROWS = 3;

// m = Config.dashboard (see DashboardModule layout):
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
