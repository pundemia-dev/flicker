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
        key: Qt.md5(visiblePath + "|" + mtimeText + "|" + sizeText)
    };
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
