import QtQuick
import Quickshell
import Quickshell.Io

// Capture command builders + session memories (port of pShell
// services/Capture). WM-agnostic: grim/magick/wl-copy work on niri and
// driftwm alike; recording itself lives in the Recorder service.
Scope {
    id: root
    required property var cfg

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string tempDir: root.expand(root.cfg.tempDir)
    readonly property string saveDir: root.expand(root.cfg.saveDir ?? "")

    // Session memories ("auto" defaults) and pipette history (newest first).
    property string lastColorFormat: "hex"
    property string lastOcrLangs: ""
    property var recentColors: []
    // Smart-region boxes per grab path (one grab = one detection).
    property var smartCache: ({})

    function cacheSmart(src: string, rects: var): void {
        // Keep only this session's grabs (paths share the "-<stamp>.ppm" tail).
        const tail = src.slice(src.lastIndexOf("-"));
        const c = {};
        for (const k in root.smartCache)
            if (k.endsWith(tail))
                c[k] = root.smartCache[k];
        c[src] = rects;
        root.smartCache = c;
    }

    // Installed tesseract languages ("osd" is a script detector, skipped).
    property var ocrLangsAvailable: []

    function expand(p: string): string {
        return p.startsWith("~") ? root.home + p.slice(1) : p;
    }

    function shq(s: string): string {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    function stamp(): string {
        return Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH.mm.ss");
    }

    // Frozen per-output grab (PPM: lossless, no encode → ~60ms here). Stamped
    // per session so Qt's image cache never serves an old frame.
    function srcPath(name: string, sessionStamp: string): string {
        return `${root.tempDir}/src-${name}-${sessionStamp}.ppm`;
    }

    function scratchPng(kind: string, name: string): string {
        return `${root.tempDir}/${kind}-${name}.png`;
    }

    // One process grabs every output in parallel; stale grabs are removed.
    function grabCommand(names: var, sessionStamp: string): var {
        const shots = names.map(n => `grim -t ppm -o ${root.shq(n)} ${root.shq(root.srcPath(n, sessionStamp))} &`).join(" ");
        return ["bash", "-c", `mkdir -p ${root.shq(root.tempDir)} && rm -f ${root.shq(root.tempDir)}/src-* ; ${shots} wait`];
    }

    // Shell snippet: clipboard and/or a dated copy in saveDir, with feedback.
    function deliverShell(file: string, copy: bool, save: bool): string {
        const parts = [];
        if (copy || !save || !root.saveDir)
            parts.push(`wl-copy -t image/png < ${root.shq(file)}`);
        if (save && root.saveDir) {
            const path = `${root.saveDir}/screenshot-${root.stamp()}.png`;
            parts.push(`mkdir -p ${root.shq(root.saveDir)} && cp ${root.shq(file)} ${root.shq(path)} && notify-send -a pillShell 'Скриншот сохранён' ${root.shq(path)}`);
        } else {
            parts.push(`notify-send -a pillShell 'Скриншот скопирован'`);
        }
        return parts.join(" && ");
    }

    function deliver(file: string, copy: bool, save: bool): void {
        Quickshell.execDetached(["bash", "-c", root.deliverShell(file, copy, save)]);
    }

    // Plain commit (Enter / IPC): config decides clipboard vs file.
    function deliverDefault(file: string): void {
        root.deliver(file, root.cfg.copyToClipboard, root.saveDir !== "");
    }

    // Physical-px crop of a grab into a PNG.
    function cropCommand(src: string, r: var, out: string): var {
        return ["bash", "-c", `magick ${root.shq(src)} -crop ${r.width}x${r.height}+${r.x}+${r.y} +repage ${root.shq(out)}`];
    }

    // Instant full-output screenshot (IPC, no overlay).
    function screenshotOutput(name: string): void {
        const file = root.scratchPng("screen", name);
        Quickshell.execDetached(["bash", "-c", `mkdir -p ${root.shq(root.tempDir)} && grim -o ${root.shq(name)} ${root.shq(file)} && `
            + root.deliverShell(file, root.cfg.copyToClipboard, root.saveDir !== "")]);
    }

    function copyText(text: string, summary: string): void {
        const note = summary ? ` && notify-send -a pillShell ${root.shq(summary)}` : "";
        Quickshell.execDetached(["bash", "-c", `printf '%s' ${root.shq(text)} | wl-copy${note}`]);
    }

    // Google Lens: crop the pure grab → temp host → Lens in the browser.
    function lens(src: string, r: var, name: string): void {
        const file = root.scratchPng("lens", name);
        Quickshell.execDetached(["bash", "-c", `magick ${root.shq(src)} -crop ${r.width}x${r.height}+${r.x}+${r.y} +repage ${root.shq(file)}`
            + ` && url="$(curl -sf -F "files[]=@${file}" ${root.shq(root.cfg.lensUploadUrl)} | jq -r '.files[0].url')"`
            + ` && [ -n "$url" ] && [ "$url" != null ] && xdg-open "https://lens.google.com/uploadbyurl?url=$url"`
            + ` || notify-send -a pillShell 'Google Lens' 'Не удалось загрузить'`]);
        Quickshell.execDetached(["notify-send", "-a", "pillShell", "Google Lens", "Загружаю фрагмент…"]);
    }

    // scripts/capture/<name> (uv inline-deps script). Offline first: online
    // `uv run --script` re-resolves the deps on every start (~55s here);
    // the online run only happens until the env is cached.
    function uvScript(name: string, args: var): var {
        const cmd = `uv run --quiet --script ${root.shq(`${Quickshell.shellDir}/scripts/capture/${name}`)} ${args.map(a => root.shq(a)).join(" ")}`;
        return ["bash", "-c", `${cmd.replace("uv run", "uv run --offline")} 2>/dev/null || ${cmd}`];
    }

    function addRecent(r: int, g: int, b: int): void {
        const hex = "#" + [r, g, b].map(v => v.toString(16).padStart(2, "0")).join("");
        const list = root.recentColors.filter(c => c.hex !== hex);
        list.unshift({ hex: hex, r: r, g: g, b: b });
        root.recentColors = list.slice(0, root.cfg.recentColors);
    }

    Process {
        running: true
        command: ["bash", "-c", "tesseract --list-langs 2>/dev/null | tail -n +2"]
        stdout: StdioCollector {
            id: langsOut
            onStreamFinished: root.ocrLangsAvailable = langsOut.text.trim().split("\n").filter(l => l && l !== "osd")
        }
    }
}
