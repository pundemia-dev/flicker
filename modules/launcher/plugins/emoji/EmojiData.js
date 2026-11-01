.pragma library

// Parsed emoji.tsv (scripts/launcher/gen_emoji_data.py), shared by every
// plugin instance: the launcher rebuilds its plugins on each open, the
// dataset is parsed once per shell.
// Row: { ch, group, name, ru, emoji (colour glyph), search (lowercase) }.

// Emoji groups (emoji-test order) first, then the symbol groups.
const EMOJI_GROUPS = ["Smileys & Emotion", "People & Body", "Animals & Nature", "Food & Drink",
    "Travel & Places", "Activities", "Objects", "Symbols", "Flags"];

// Tab glyph per group.
const GLYPHS = {
    "Smileys & Emotion": "😀", "People & Body": "👋", "Animals & Nature": "🐻",
    "Food & Drink": "🍔", "Travel & Places": "🚗", "Activities": "⚽", "Objects": "💡",
    "Symbols": "❤️", "Flags": "🏁",
    "Punctuation": "«»", "Arrows": "→", "Math": "∑", "Currency": "₽", "Technical": "⌘",
    "Letterlike": "№", "Superscripts": "x²", "Greek": "α", "Shapes": "■", "Dingbats": "★",
    "Other symbols": "﷼"
};

let rows = null;
let groups = [];
let byChar = null;

function load(text) {
    if (rows)
        return;
    const out = [];
    const seen = [];
    byChar = {};
    const lines = text.split("\n");
    for (let i = 0; i < lines.length; i++) {
        const f = lines[i].split("\t");
        if (f.length < 3 || f[0] === "")
            continue;
        const r = {
            ch: f[0],
            group: f[1],
            name: f[2],
            ru: f[3] || "",
            emoji: EMOJI_GROUPS.indexOf(f[1]) >= 0,
            search: (f[2] + " " + (f[3] || "") + " " + (f[4] || "")).toLowerCase()
        };
        if (seen.indexOf(r.group) < 0)
            seen.push(r.group);
        out.push(r);
        byChar[r.ch] = r;
    }
    rows = out;
    groups = seen;
}

function loaded() {
    return rows !== null;
}

function groupList() {
    return groups;
}

function glyph(group) {
    return GLYPHS[group] || "•";
}

function inGroup(group) {
    return rows ? rows.filter(r => r.group === group) : [];
}

function lookup(chars) {
    if (!rows)
        return [];
    return chars.map(c => byChar[c]).filter(r => !!r);
}

// Every term must occur (name, Russian name, CLDR keywords); rows whose
// name has a word starting with the first term come first, then the rest
// in dataset order. A query that is the character itself finds it too.
function search(query) {
    if (!rows)
        return [];
    const q = query.trim().toLowerCase();
    if (q === "")
        return [];
    const terms = q.split(/\s+/);
    const first = [], rest = [];
    for (let i = 0; i < rows.length; i++) {
        const r = rows[i];
        if (r.ch === query.trim()) {
            first.unshift(r);
            continue;
        }
        let ok = true;
        for (let t = 0; t < terms.length && ok; t++)
            ok = r.search.indexOf(terms[t]) >= 0;
        if (!ok)
            continue;
        const words = (r.name + " " + r.ru).toLowerCase().split(/[\s,:«»()-]+/);
        (words.some(w => w.startsWith(terms[0])) ? first : rest).push(r);
    }
    return first.concat(rest);
}
