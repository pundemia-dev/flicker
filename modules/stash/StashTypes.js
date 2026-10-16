.pragma library

// What a tray file is (by extension; folders by the scanner's trailing /):
// one source for the tile icon / thumbnail, the menu actions and the
// Quick Look preview.

const IMAGE = ["png", "jpg", "jpeg", "webp", "bmp", "svg", "avif", "tif", "tiff", "ico"];
const ANIMATED = ["gif", "apng"];
const VIDEO = ["mp4", "mkv", "avi", "mov", "webm", "m4v"];
const AUDIO = ["mp3", "wav", "flac", "ogg", "aac", "m4a", "opus", "wma", "amr", "aiff", "aif"];
const TEXT = ["txt", "md", "log", "csv", "json", "xml", "toml", "yaml", "yml", "sh", "py", "js", "ts", "rs", "go", "cpp", "c", "h", "qml", "srt", "ini", "conf", "html", "css"];
const ARCHIVE = ["zip", "tar", "gz", "bz2", "xz", "rar", "7z", "zst", "tgz", "iso"];

function ext(name) {
    return name.includes(".") ? name.split(".").pop().toLowerCase() : "";
}

// image | animated | video | audio | pdf | text | archive | dir | other
function kindOf(name, isDir) {
    if (isDir)
        return "dir";
    const e = ext(name);
    if (IMAGE.includes(e))
        return "image";
    if (ANIMATED.includes(e))
        return "animated";
    if (VIDEO.includes(e))
        return "video";
    if (AUDIO.includes(e))
        return "audio";
    if (e === "pdf")
        return "pdf";
    if (TEXT.includes(e))
        return "text";
    if (ARCHIVE.includes(e))
        return "archive";
    return "other";
}

function themeIcon(kind) {
    return {
        image: "image-x-generic", animated: "image-x-generic", pdf: "application-pdf",
        video: "video-x-generic", audio: "audio-x-generic", text: "text-x-generic",
        archive: "application-x-archive", dir: "folder"
    }[kind] ?? "application-x-generic";
}

// Tile menu actions (StashTileMenu): t = StashTile, tr = I18n.tr.
function actions(t, tr) {
    if (!t)
        return [];
    const out = [
        { key: "preview", glyph: "", label: tr("Preview") },
        { key: "open", glyph: "", label: tr("Open") }
    ];
    if (t.localSend?.enabled)
        out.push({ key: "send", glyph: "", label: tr("Send"), accent: true });
    out.push({ key: "fav", glyph: "", label: t.isFav ? tr("Unpin") : tr("Pin"), checked: t.isFav });
    if (t.canTranscribe)
        out.push({ key: "transcribe", glyph: "", label: tr("Transcript"), checked: t.trState === "done" });
    out.push(t.kind === "archive"
        ? { key: "unpack", glyph: "", label: tr("Extract") }
        : { key: "pack", glyph: "", label: tr("Compress") });
    out.push({ key: "select", glyph: "", label: tr("Select") });
    out.push({ key: "delete", glyph: "", label: tr("Delete"), danger: true });
    return out;
}
