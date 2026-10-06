import QtQuick
import Quickshell
import Quickshell.Io
import "WallrArgs.js" as WallrArgs

// Wallpaper files + thumbnails + the wallr backend for the carousel.
// Files: scripts/wallpapers/scan.sh over cfg.dirs (rescanned only when the
// directory signature changes, polled every cfg.rescanMs while `watching`).
// Entries are stable objects per path+mtime+size (the carousel's window
// model diffs by identity). Thumbnails are made ON DEMAND for what the
// carousel asks for (`want`, nearest first) — the folder can hold thousands
// of files — by scripts/wallpapers/thumbs.sh into cacheDir/<key>.jpg.
Item {
    id: root
    property var cfg: null
    property bool watching: false

    readonly property string scripts: Quickshell.shellDir + "/scripts/wallpapers/"
    readonly property string cacheDir: {
        const d = root.cfg?.cacheDir ?? "";
        if (d.length)
            return d.replace(/^~/, Quickshell.env("HOME"));
        const x = Quickshell.env("XDG_CACHE_HOME");
        return ((x && x.length) ? x : Quickshell.env("HOME") + "/.cache") + "/pillShell/wallpapers";
    }

    // [{ path, name, type: image|gif|video, mtime, size, key }]
    property var files: []
    property bool loaded: false
    // key -> true once its thumbnail file exists (reassigned: bindings
    // read thumbUrl()).
    property var thumbs: ({})
    property var failed: ({})

    function typeOf(path: string): string {
        const ext = path.slice(path.lastIndexOf(".") + 1).toLowerCase();
        if (ext === "gif")
            return "gif";
        if (["mp4", "webm", "mkv", "mov"].includes(ext))
            return "video";
        return "image";
    }

    function thumbUrl(entry: var): string {
        return entry && root.thumbs[entry.key] ? "file://" + root.cacheDir + "/" + entry.key + ".jpg" : "";
    }

    // ---- scan ----

    property string signature: ""
    property var entryCache: new Map()

    function scanArgs(mode: string): var {
        return [root.scripts + "scan.sh", mode, (root.cfg?.recursive ?? true) ? "1" : "0"].concat(root.cfg?.dirs ?? []);
    }

    function rescan(): void {
        if (scanProc.running) {
            root.rescanQueued = true;
            return;
        }
        scanProc.command = root.scanArgs("files");
        scanProc.running = true;
    }
    property bool rescanQueued: false

    Process {
        id: scanProc
        stdout: StdioCollector {
            onStreamFinished: root.parseFiles(this.text)
        }
        onExited: if (root.rescanQueued) {
            root.rescanQueued = false;
            root.rescan();
        }
    }

    function parseFiles(text: string): void {
        const live = new Map();
        const list = [];
        for (const line of text.split("\n")) {
            const t = line.split("\t");
            if (t.length < 3)
                continue;
            const path = t.slice(2).join("\t");
            const id = path + "|" + t[0] + "|" + t[1];
            let e = root.entryCache.get(id);
            if (!e) {
                const slash = path.lastIndexOf("/");
                e = {
                    path: path,
                    name: path.slice(slash + 1).replace(/\.[^.]+$/, ""),
                    type: root.typeOf(path),
                    mtime: parseFloat(t[0]),
                    size: parseInt(t[1]),
                    key: Qt.md5(id)
                };
            }
            live.set(id, e);
            list.push(e);
        }
        root.entryCache = live;
        if ((root.cfg?.sort ?? "name") === "mtime")
            list.sort((a, b) => b.mtime - a.mtime);
        else
            list.sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true }));
        root.files = list;
        root.loaded = true;
    }

    // Directory signature poll: a full rescan only when it changes.
    Timer {
        interval: root.cfg?.rescanMs ?? 2000
        repeat: true
        running: root.watching
        onTriggered: if (!sigProc.running) {
            sigProc.command = root.scanArgs("sig");
            sigProc.running = true;
        }
    }
    Process {
        id: sigProc
        stdout: StdioCollector {
            onStreamFinished: {
                const s = this.text.trim();
                if (root.signature && s !== root.signature)
                    root.rescan();
                root.signature = s;
            }
        }
    }

    onWatchingChanged: if (watching) {
        root.listThumbs();
        root.rescan();
        sigProc.command = root.scanArgs("sig");
        sigProc.running = true;
    }

    // Existing thumbnails (one ls per session start).
    function listThumbs(): void {
        lsProc.command = ["bash", "-c", "mkdir -p \"$1\"; ls -1 \"$1\"", "ls", root.cacheDir];
        lsProc.running = true;
    }
    Process {
        id: lsProc
        stdout: StdioCollector {
            onStreamFinished: {
                const t = Object.assign({}, root.thumbs);
                for (const f of this.text.split("\n"))
                    if (f.endsWith(".jpg") && !f.startsWith("."))
                        t[f.slice(0, -4)] = true;
                root.thumbs = t;
                root.pump();
            }
        }
    }

    // ---- thumbnails on demand ----

    // Entries the carousel wants, nearest to the selection first.
    property var wanted: []
    readonly property int batch: root.cfg?.thumbBatch ?? 9
    readonly property int jobs: root.cfg?.thumbJobs ?? 3

    function want(entries: var): void {
        root.wanted = entries;
        root.pump();
    }

    function pump(): void {
        if (thumbProc.running || lsProc.running)
            return;
        const args = [];
        for (const e of root.wanted) {
            if (root.thumbs[e.key] || root.failed[e.key])
                continue;
            args.push(e.key, e.path);
            if (args.length >= root.batch * 2)
                break;
        }
        if (!args.length)
            return;
        thumbProc.command = [root.scripts + "thumbs.sh", root.cacheDir, String(root.cfg?.thumbHeight ?? 460), String(root.jobs)].concat(args);
        thumbProc.running = true;
    }

    Process {
        id: thumbProc
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("!")) {
                    const f = Object.assign({}, root.failed);
                    f[line.slice(1)] = true;
                    root.failed = f;
                    return;
                }
                const t = Object.assign({}, root.thumbs);
                t[line] = true;
                root.thumbs = t;
            }
        }
        onExited: root.pump()
    }

    // ---- wallr ----

    // Current wallpaper of an output (wallr's own state file).
    function readCurrent(output: string, done: var): void {
        const p = Quickshell.env("HOME") + "/.cache/wallr/last_wallpaper/" + output;
        currentProc.done = done;
        currentProc.command = ["cat", p];
        currentProc.running = true;
    }
    Process {
        id: currentProc
        property var done: null
        stdout: StdioCollector {
            onStreamFinished: if (currentProc.done)
                currentProc.done(this.text.trim())
        }
    }

    // Detached: a set must survive the launcher closing (restore on close
    // runs from onDestruction).
    function set(path: string, opts: var): void {
        Quickshell.execDetached(WallrArgs.set(path, opts, root.cfg?.mode ?? ""));
    }
}
