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

// Titles are English I18n keys: translate at the display site (I18n.tr).
const CARDS = {
    wifi: { glyph: "\ueb52", title: "Wi‑Fi", sizes: BUTTON_WIDE },
    bluetooth: { glyph: "\uea37", title: "Bluetooth", sizes: BUTTON_WIDE },
    hotspot: { glyph: "\ued1b", title: "Hotspot", sizes: BUTTON_SMALL },
    vpn: { glyph: "\ued58", title: "VPN", sizes: BUTTON_WIDE },
    dnd: { glyph: "\uf684", title: "Do Not Disturb", sizes: BUTTON_SMALL },
    mic: { glyph: "\ueaf0", title: "Microphone", sizes: BUTTON_SMALL },
    volume: { glyph: "\ueb51", title: "Volume", sizes: [[1, 2], [1, 1], [2, 1], [4, 1], [1, 3], [2, 2]] },
    brightness: { glyph: "\uD800\uDD08", title: "Brightness", sizes: [[1, 2], [1, 1], [2, 1], [4, 1], [1, 3], [2, 2]] },
    media: { glyph: "\ueafc", title: "Music", sizes: [[2, 2], [1, 1], [2, 1], [4, 1], [4, 2], [4, 4], [4, 6]] },
    record: { glyph: "\ued47", title: "Screen Recording", sizes: BUTTON_SMALL },
    screenshot: { glyph: "\uf201", title: "Screenshot", sizes: BUTTON_SMALL },
    slideshow: { glyph: "\uebc9", title: "Slideshow", sizes: BUTTON_SMALL },
    shazam: { glyph: "\uedd6", title: "Shazam", sizes: BUTTON_SMALL },
    // Stubs (no backend yet, cards/QsCardFactory stubComp): start hidden.
    magnifier: { glyph: "\ueb56", title: "Magnifier", sizes: BUTTON_SMALL },
    voiceMemos: { glyph: "\uecd4", title: "Voice Memos", sizes: BUTTON_SMALL },
    scanCode: { glyph: "\ueb11", title: "Scan Code", sizes: BUTTON_SMALL },
    notes: { glyph: "\ueb6e", title: "Notes", sizes: BUTTON_SMALL },
    translate: { glyph: "\uebbe", title: "Translate", sizes: BUTTON_WIDE },
    lowPower: { glyph: "\uef3c", title: "Low Power Mode", sizes: BUTTON_SMALL },
    airplane: { glyph: "\ueb6f", title: "Airplane Mode", sizes: BUTTON_SMALL },
    caffeine: { glyph: "\uef0e", title: "Caffeine", sizes: BUTTON_SMALL },
    cellular: { glyph: "\ueccb", title: "Cellular Data", sizes: BUTTON_SMALL },
    dictation: { glyph: "\uef2c", title: "Dictation", sizes: BUTTON_SMALL },
    stopwatch: { glyph: "\uff9b", title: "Stopwatch", sizes: BUTTON_SMALL },
    timer: { glyph: "\uef93", title: "Timer", sizes: BUTTON_SMALL },
    localsend: { glyph: "\ueb1e", title: "LocalSend", sizes: BUTTON_SMALL },
    calculator: { glyph: "\ueb80", title: "Calculator", sizes: BUTTON_SMALL },
    mirroring: { glyph: "\ued18", title: "Screen Mirroring", sizes: BUTTON_WIDE },
    focus: { glyph: "\uebd3", title: "Focus", sizes: BUTTON_WIDE }
};

// Stable order (Repeater model: delegates are never recreated, cards
// hidden/shown by visibility).
const IDS = Object.keys(CARDS);

// W W M M   W = wifi 2x1, B = bluetooth 2x1, M = media 2x2
// B B M M   D = dnd, m = mic, H = hotspot, R = record (1x1)
// D m V L   V = volume 1x2, L = brightness 1x2
// H R V L   screenshot, slideshow, shazam, vpn and the stubs start hidden (edit footer → add)
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
