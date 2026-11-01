.pragma library

// One wallpaper file as the carousel, the slideshow and the thumbnail
// warm-up see it (scripts/wallpapers/scan.sh "files" lines).
// Hidden = ".name" (hide/unhide renames). The thumbnail key ignores the
// dot, so hiding/unhiding keeps the cached thumbnail; it hashes the RAW
// scan strings (mtime/size text) — the same key everywhere.

function typeOf(path) {
    const ext = path.slice(path.lastIndexOf(".") + 1).toLowerCase();
    if (ext === "gif")
        return "gif";
    if (["mp4", "webm", "mkv", "mov"].includes(ext))
        return "video";
    return "image";
}

function make(path, mtimeText, sizeText) {
    const slash = path.lastIndexOf("/");
    const base = path.slice(slash + 1);
    const hidden = base.startsWith(".");
    const visiblePath = hidden ? path.slice(0, slash + 1) + base.slice(1) : path;
    return {
        path: path,
        name: (hidden ? base.slice(1) : base).replace(/\.[^.]+$/, ""),
        hidden: hidden,
        type: typeOf(path),
        mtime: parseFloat(mtimeText),
        size: parseInt(sizeText),
        mtimeText: mtimeText,
        sizeText: sizeText,
        // Lazy: md5 over ~5000 files was most of a ~0.7 s stall on open;
        // only cards on screen (thumbnails) and the semantic view read it.
        get key() {
            if (this._key === undefined)
                this._key = Qt.md5(visiblePath + "|" + mtimeText + "|" + sizeText);
            return this._key;
        }
    };
}

// Scan lines → entries, reusing the entry of every unchanged line (stable
// identity: the carousel's window model diffs by it). The cache lives in
// this library (one per engine), not in the service: the launcher rebuilds
// the plugin on every open, and an empty cache re-made every entry. A plain
// object, not a Map: QV4's Map lookups are linear — 5000 get/set took
// ~0.3 s even with every line cached.
let cache = Object.create(null);
function fromLines(lines) {
    const live = Object.create(null);
    const list = [];
    for (const l of lines) {
        const e = cache[l.id] ?? make(l.path, l.mtimeText, l.sizeText);
        live[l.id] = e;
        list.push(e);
    }
    cache = live;
    return list;
}

// scan.sh output → [{ line id, path, mtimeText, sizeText }] (no entries
// built: callers cache by id).
function lines(text) {
    const out = [];
    for (const line of text.split("\n")) {
        const t = line.split("\t");
        if (t.length < 3)
            continue;
        const path = t.slice(2).join("\t");
        out.push({ id: path + "|" + t[0] + "|" + t[1], path: path, mtimeText: t[0], sizeText: t[1] });
    }
    return out;
}

// Carousel order (cfg.sort): name (natural) or mtime (newest first).
function sort(list, by) {
    if (by === "mtime")
        list.sort((a, b) => b.mtime - a.mtime);
    else
        list.sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true }));
    return list;
}

// The whole scan → sorted list, memoised on the scan text: the launcher
// rebuilds the plugin on every open and rescans, and the answer is nearly
// always the same — no re-parse, no re-sort (~0.1 s on ~5000 names). `last`
// seeds a new service, so the carousel has its cards from the first frame
// instead of after the scan.
let lastText = null;
let lastBy = "";
let lastList = [];
function parse(text, by) {
    if (text !== lastText || by !== lastBy) {
        lastList = sort(fromLines(lines(text)), by);
        lastText = text;
        lastBy = by;
    }
    return lastList;
}
function last(by) {
    return by === lastBy ? lastList : [];
}
// The service changed its list itself (trash, hide/unhide): seed the next
// one with it, and forget the scan text: a failed trash rescans to the
// SAME text, which must not return the list without the file.
function remember(list) {
    lastList = list;
    lastText = null;
}
