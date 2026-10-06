import QtQuick
import Quickshell
import Quickshell.Io

// cliphist backend of the clipboard plugin (pShell ClipboardService port;
// lives only inside the plugin). Lists the history, classifies entries
// (image / color / url / path / text) and decodes image thumbnails into
// cfg.cacheDir in one batch before publishing, so `imagePath` always
// exists. History only fills while `wl-paste --watch cliphist store` runs
// (niri spawns it at startup; other compositors need it too).
Item {
    id: root
    required property var cfg

    // Newest first: { raw, id, type, ... }.
    property var records: []

    readonly property string binary: "cliphist"
    readonly property int historyLimit: root.cfg?.historyLimit ?? 100
    readonly property bool autoPaste: root.cfg?.autoPaste ?? false
    readonly property string pasteCommand: root.cfg?.pasteCommand ?? "wtype -M ctrl v -m ctrl"
    readonly property string cacheDir: {
        const d = root.cfg?.cacheDir ?? "";
        if (d)
            return d.replace(/^~/, Quickshell.env("HOME"));
        const x = Quickshell.env("XDG_CACHE_HOME");
        return ((x && x.length) ? x : Quickshell.env("HOME") + "/.cache") + "/pillShell/clipboard";
    }

    function shq(s: string): string {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    readonly property var reImage: /\[\[\s*binary data.*\]\]/i
    readonly property var reDims: /(\d+)x(\d+)/
    readonly property var reSize: /binary data\s+([\d.]+\s*\w+)/i
    readonly property var reHex: /^#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/
    readonly property var reRgb: /^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)$/i
    readonly property var reHsl: /^hsla?\(\s*([\d.]+)\s*,\s*([\d.]+)%\s*,\s*([\d.]+)%\s*(?:,\s*([\d.]+)\s*)?\)$/i
    readonly property var reUrl: /^https?:\/\/\S+$/i
    readonly property var rePath: /^(file:\/\/|\/)\S/

    function classify(raw: string): var {
        const tab = raw.indexOf("\t");
        const id = tab >= 0 ? raw.slice(0, tab) : raw;
        const preview = tab >= 0 ? raw.slice(tab + 1) : raw;
        const trimmed = preview.trim();

        if (reImage.test(preview)) {
            const d = preview.match(reDims);
            const s = preview.match(reSize);
            return {
                raw, id, type: "image",
                width: d ? parseInt(d[1]) : 0,
                height: d ? parseInt(d[2]) : 0,
                size: s ? s[1] : "",
                imagePath: cacheDir + "/" + id
            };
        }
        const hex = colorToHex(trimmed);
        if (hex)
            return { raw, id, type: "color", value: trimmed, hex,
                     label: reHex.test(trimmed) ? "HEX" : (reRgb.test(trimmed) ? "RGB" : "HSL") };
        if (reUrl.test(trimmed))
            return { raw, id, type: "url", value: trimmed, host: trimmed.replace(/^https?:\/\//i, "").split("/")[0] };
        if (rePath.test(trimmed) && trimmed.indexOf("\n") < 0) {
            const clean = trimmed.replace(/^file:\/\//i, "");
            const parts = clean.split("/");
            const base = parts.pop() || clean;
            return { raw, id, type: "path", value: clean, base, dir: parts.join("/") || "/" };
        }
        const lines = preview.split("\n");
        return { raw, id, type: "text", value: trimmed,
                 firstLine: (lines[0] || "").trim() || trimmed,
                 chars: preview.length, lineCount: lines.length };
    }

    // CSS hex/rgb/hsl → "#RRGGBB(AA)", or "".
    function colorToHex(s: string): string {
        if (reHex.test(s))
            return s;
        let m = s.match(reRgb);
        if (m)
            return rgbaHex(+m[1], +m[2], +m[3], m[4] === undefined ? 1 : +m[4]);
        m = s.match(reHsl);
        if (m) {
            const c = Qt.hsla(((+m[1] % 360) + 360) % 360 / 360, +m[2] / 100, +m[3] / 100, 1);
            return rgbaHex(c.r * 255, c.g * 255, c.b * 255, m[4] === undefined ? 1 : +m[4]);
        }
        return "";
    }

    function rgbaHex(r: real, g: real, b: real, a: real): string {
        const h = v => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, "0");
        return "#" + (a < 1 ? h(a * 255) : "") + h(r) + h(g) + h(b);
    }

    property var pending: []

    function refresh(): void {
        if (listProc.running)
            return;
        listProc.buffer = [];
        listProc.running = true;
    }

    function finalize(lines: var): void {
        const recs = lines.slice(0, historyLimit).map(l => classify(l));
        const images = recs.filter(r => r.type === "image");
        if (images.length === 0) {
            records = recs;
            return;
        }
        // Decode missing thumbnails in one shell call, then publish.
        pending = recs;
        const cmds = images.map(im => {
            const f = shq(im.imagePath);
            return `[ -s ${f} ] || printf %s ${shq(im.raw)} | ${binary} decode > ${f} 2>/dev/null`;
        });
        thumbProc.command = ["bash", "-c", `mkdir -p ${shq(cacheDir)}; ` + cmds.join("; ")];
        thumbProc.running = true;
    }

    // Puts the entry back on the clipboard (images as their binary).
    function copy(rec: var, paste: bool): void {
        let cmd = `printf %s ${shq(rec.raw)} | ${binary} decode | wl-copy`;
        if (paste)
            cmd += `; sleep 0.06; ${pasteCommand}`;
        Quickshell.execDetached(["bash", "-c", cmd]);
    }

    function remove(rec: var): void {
        deleteProc.command = ["bash", "-c", `printf %s ${shq(rec.raw)} | ${binary} delete`];
        deleteProc.running = true;
    }

    Process {
        id: listProc
        property var buffer: []
        command: [root.binary, "list"]
        stdout: SplitParser {
            onRead: line => listProc.buffer.push(line)
        }
        onExited: (code, status) => {
            if (code === 0)
                root.finalize(listProc.buffer);
            else
                console.warn("[Clipboard] cliphist list failed:", code);
        }
    }

    Process {
        id: thumbProc
        onExited: root.records = root.pending
    }

    Process {
        id: deleteProc
        onExited: root.refresh()
    }

    // Text copies while the launcher is open.
    Connections {
        target: Quickshell
        function onClipboardTextChanged(): void {
            watchTimer.restart();
        }
    }

    Timer {
        id: watchTimer
        interval: 120
        onTriggered: root.refresh()
    }
}
