.pragma library

// Every card the dashboard knows: allowed footprints ([cols, rows], first =
// default when added back), the edit-footer glyph and the stock layout.
// Sizes are the ones each card's content is built to fill (cards lay out by
// their allocated rect, see cards/*.qml) — a card never gets a shape it
// cannot draw. Layout engine = modules/quicksettings/QsGrid.js (shared).

// Titles are English I18n keys: translate at the display site (I18n.tr).
const CARDS = {
    calendar: { glyph: "", title: "Calendar", sizes: [[2, 2], [3, 3]] },
    weather: { glyph: "", title: "Weather", sizes: [[4, 1], [5, 1], [6, 1], [8, 1]] },
    media: { glyph: "", title: "Music", sizes: [[2, 2], [3, 2], [4, 2], [3, 3]] },
    system: { glyph: "", title: "Load", sizes: [[2, 2], [3, 2], [2, 3], [3, 3]] },
    battery: { glyph: "", title: "Battery", sizes: [[2, 1], [3, 1], [4, 1]] },
    sensors: { glyph: "", title: "Sensors", sizes: [[2, 1], [3, 1], [4, 1], [2, 2]] },
    processes: { glyph: "", title: "Processes", sizes: [[4, 1], [3, 1], [5, 1], [6, 1], [4, 2]] },
    // Off the stock layout (edit footer → add).
    updates: { glyph: "", title: "Updates", sizes: [[2, 1], [3, 1], [2, 2]] },
    events: { glyph: "", title: "Events", sizes: [[2, 1], [2, 2], [3, 2]] }
};

// Stable order (Repeater model: delegates are never recreated, cards
// hidden/shown by visibility).
const IDS = Object.keys(CARDS);

// K K W W W W M M   K = calendar 2x2,  W = weather 4x1
// K K S S B B M M   M = media 2x2,     S = system 2x2
// T T S S P P P P   B = battery 2x1,   P = processes 4x1
//                   T = sensors 2x1
const DEFAULT_LAYOUT = [
    { id: "calendar", x: 0, y: 0, w: 2, h: 2 },
    { id: "weather", x: 2, y: 0, w: 4, h: 1 },
    { id: "media", x: 6, y: 0, w: 2, h: 2 },
    { id: "system", x: 2, y: 1, w: 2, h: 2 },
    { id: "battery", x: 4, y: 1, w: 2, h: 1 },
    { id: "sensors", x: 0, y: 2, w: 2, h: 1 },
    { id: "processes", x: 4, y: 2, w: 4, h: 1 }
];

function sizesOf(id) {
    return CARDS[id]?.sizes ?? [[1, 1]];
}

function allowed(id, w, h) {
    return sizesOf(id).some(s => s[0] === w && s[1] === h);
}

// Drops unknown ids, duplicates and footprints the card no longer allows
// (state file from an older catalog).
function sanitize(items) {
    const seen = {};
    const out = [];
    for (const i of items ?? []) {
        if (!CARDS[i?.id] || seen[i.id])
            continue;
        seen[i.id] = true;
        const ok = allowed(i.id, i.w, i.h);
        const s = sizesOf(i.id)[0];
        out.push({ id: i.id, x: i.x | 0, y: i.y | 0, w: ok ? i.w : s[0], h: ok ? i.h : s[1] });
    }
    return out;
}

function glyphOf(id) {
    return CARDS[id]?.glyph ?? "";
}

function titleOf(id) {
    return CARDS[id]?.title ?? id;
}
