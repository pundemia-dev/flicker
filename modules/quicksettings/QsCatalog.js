.pragma library

// Every card Quick Settings knows: allowed footprints ([cols, rows], first
// = default when added), the edit-footer glyph and the stock layout. The
// card's CONTENT layout follows its shape (QsCard.form: small 1x1, wide
// Nx1, tall 1xN, large NxN, panorama wider than tall and >= 2 rows; media
// keys its own layout by footprint) — see each card file.

// Default buttons (cards/ButtonCard.qml): 1x1 glyph, 2x1 glyph + text,
// 2x2 glyph top-left + text bottom. First = default when added.
const BUTTON_WIDE = [[2, 1], [1, 1], [2, 2]];
const BUTTON_SMALL = [[1, 1], [2, 1], [2, 2]];

const CARDS = {
    wifi: { glyph: "\ueb52", title: "Wi‑Fi", sizes: BUTTON_WIDE },
    bluetooth: { glyph: "\uea37", title: "Bluetooth", sizes: BUTTON_WIDE },
    hotspot: { glyph: "\ued1b", title: "Точка доступа", sizes: BUTTON_SMALL },
    dnd: { glyph: "\uf684", title: "Не беспокоить", sizes: BUTTON_SMALL },
    mic: { glyph: "\ueaf0", title: "Микрофон", sizes: BUTTON_SMALL },
    volume: { glyph: "\ueb51", title: "Громкость", sizes: [[1, 2], [1, 1], [2, 1], [4, 1], [1, 3], [2, 2]] },
    brightness: { glyph: "\uD800\uDD08", title: "Яркость", sizes: [[1, 2], [1, 1], [2, 1], [4, 1], [1, 3], [2, 2]] },
    media: { glyph: "\ueafc", title: "Музыка", sizes: [[2, 2], [1, 1], [2, 1], [4, 1], [4, 2], [4, 4], [4, 6]] },
    record: { glyph: "\ued47", title: "Запись экрана", sizes: BUTTON_SMALL },
    screenshot: { glyph: "\uf201", title: "Снимок экрана", sizes: BUTTON_SMALL }
};

// Stable order (Repeater model: delegates are never recreated, cards
// hidden/shown by visibility).
const IDS = Object.keys(CARDS);

// W W M M   W = wifi 2x1, B = bluetooth 2x1, M = media 2x2
// B B M M   D = dnd, m = mic, H = hotspot, R = record (1x1)
// D m V L   V = volume 1x2, L = brightness 1x2
// H R V L   screenshot starts hidden (edit footer → add)
const DEFAULT_LAYOUT = [
    { id: "wifi", x: 0, y: 0, w: 2, h: 1 },
    { id: "bluetooth", x: 0, y: 1, w: 2, h: 1 },
    { id: "media", x: 2, y: 0, w: 2, h: 2 },
    { id: "dnd", x: 0, y: 2, w: 1, h: 1 },
    { id: "mic", x: 1, y: 2, w: 1, h: 1 },
    { id: "volume", x: 2, y: 2, w: 1, h: 2 },
    { id: "brightness", x: 3, y: 2, w: 1, h: 2 },
    { id: "hotspot", x: 0, y: 3, w: 1, h: 1 },
    { id: "record", x: 1, y: 3, w: 1, h: 1 }
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
