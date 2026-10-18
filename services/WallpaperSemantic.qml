import QtQuick
import Quickshell
import Quickshell.Io
import "../modules/launcher/plugins/wallpapers/WallEntry.js" as WallEntry

// Semantic wallpaper search (owned by services/Wallpaper): text → picture
// and picture → similar pictures through scripts/wallpapers/clip.py
// (mexma-siglip2 ONNX, model files in semanticModelDir). The server is
// started on demand, answers JSON lines, and exits by itself after
// semanticIdleSec; lines sent while it is down wait in `outbox` and go out
// on start. Indexing runs in its own thread inside the server (niced,
// ~3 s per thumbnail on the user's CPU) over the carousel thumbnails:
// `indexAll()` after the thumbnail warm-up goes idle (visible files first,
// hidden after or skipped — semanticIndexHidden), never on battery
// (semanticOnBattery) and never in Low Power Mode (`powerSave`, no
// override) — a running index stops when the power goes / the mode turns
// on. Only the panel's forceIndex (the user's own request) runs anyway.
// query(text, cb) / similar(key, cb) call cb({ key: score }).
Scope {
    id: root
    property var cfg: ({})
    property bool discharging: false
    property bool powerSave: false
    property string cacheDir: ""

    readonly property bool enabled: root.cfg.semanticSearch ?? true
    readonly property bool allowed: root.enabled && !root.powerSave && (!root.discharging || (root.cfg.semanticOnBattery ?? false))
    readonly property string scripts: Quickshell.shellDir + "/scripts/wallpapers/"
    readonly property string modelDir: (root.cfg.semanticModelDir ?? "~/.local/share/flicker/models/mexma-siglip2").replace(/^~/, Quickshell.env("HOME"))

    property bool indexing: false
    property int done: 0
    property int total: 0
    // Pictures in the index: read from the store itself (the server may not
    // run), refreshed as it saves (every 16 pictures).
    property int count: 0
    FileView {
        path: root.cacheDir ? root.cacheDir + "/clip/keys.json" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.count = JSON.parse(text()).length;
            } catch (e) {}
        }
    }

    property var outbox: []
    property var callbacks: ({})
    property int nextId: 1

    function send(obj: var): void {
        if (!root.enabled)
            return;
        if (server.running && server.up) {
            server.write(JSON.stringify(obj) + "\n");
            return;
        }
        root.outbox = root.outbox.concat([obj]);
        if (!server.running) {
            // Offline first (an online `uv run --script` re-resolves deps on
            // every start, CaptureActions.uvScript), online as the fallback.
            server.command = ["bash", "-c", "uv run --offline --quiet --script \"$@\" 2>/dev/null || uv run --quiet --script \"$@\" 2>/dev/null",
                "clip", root.scripts + "clip.py", root.modelDir, root.cacheDir + "/clip",
                String(root.cfg.semanticThreads ?? 6), String(root.cfg.semanticIdleSec ?? 300)];
            server.running = true;
        }
    }

    function query(text: string, cb: var): void {
        const id = root.nextId++;
        const c = Object.assign({}, root.callbacks);
        c[id] = cb;
        root.callbacks = c;
        root.send({ cmd: "query", id: id, text: text });
    }

    function similar(key: string, cb: var): void {
        const id = root.nextId++;
        const c = Object.assign({}, root.callbacks);
        c[id] = cb;
        root.callbacks = c;
        root.send({ cmd: "similar", id: id, key: key });
    }

    // Every file of the folder (keys = thumbnail keys); the server skips
    // the ones it has, and missing thumbnails. Vectors of vanished files
    // are dropped first.
    // Automatic runs (warm-up idle, opening a "? " view) respect the power
    // gate and a stop from the settings panel; `forceIndex` (panel button)
    // ignores both and is not stopped by unplugging.
    property bool forced: false
    property bool userStopped: false

    function indexAll(): void {
        if (!root.allowed || root.userStopped || root.indexing || scanProc.running)
            return;
        root.startScan();
    }

    function forceIndex(): void {
        if (!root.enabled || root.indexing || scanProc.running)
            return;
        root.userStopped = false;
        root.forced = true;
        root.startScan();
    }

    function stopIndex(): void {
        root.userStopped = true;
        root.forced = false;
        if (root.indexing)
            root.send({ cmd: "stop" });
    }

    function startScan(): void {
        scanProc.command = [root.scripts + "scan.sh", "files", (root.cfg.recursive ?? true) ? "1" : "0"].concat(root.cfg.dirs ?? []);
        scanProc.running = true;
    }

    Process {
        id: scanProc
        stdout: StdioCollector {
            onStreamFinished: {
                const all = WallEntry.lines(this.text).map(l => WallEntry.make(l.path, l.mtimeText, l.sizeText));
                if (!all.length)
                    return;
                // Visible pictures first, hidden ones after (a folder
                // can be mostly hidden files) — or not at all
                // (semanticIndexHidden). Vectors of every existing file are
                // kept either way; only vanished files are forgotten.
                const withHidden = root.cfg.semanticIndexHidden ?? true;
                const order = all.filter(e => !e.hidden).concat(withHidden ? all.filter(e => e.hidden) : []);
                root.send({ cmd: "forget", keep: all.map(e => e.key) });
                root.send({ cmd: "index", items: order.map(e => [e.key, root.cacheDir + "/" + e.key + ".jpg"]) });
                root.indexing = true;
            }
        }
    }

    onAllowedChanged: if (!root.allowed && root.indexing && !root.forced)
        root.send({ cmd: "stop" })

    Process {
        id: server
        property bool up: false
        stdinEnabled: true
        onStarted: {
            server.up = true;
            const pending = root.outbox;
            root.outbox = [];
            for (const o of pending)
                server.write(JSON.stringify(o) + "\n");
        }
        stdout: SplitParser {
            onRead: line => {
                let e;
                try {
                    e = JSON.parse(line);
                } catch (err) {
                    return;
                }
                switch (e.event) {
                case "ready":
                    root.count = e.count;
                    break;
                case "progress":
                    root.done = e.done;
                    root.total = e.total;
                    break;
                case "indexed":
                    root.indexing = false;
                    root.forced = false;
                    root.count = e.count;
                    console.info("[wallpaper] semantic index:", e.count, "pictures");
                    break;
                case "scores": {
                    const cb = root.callbacks[e.id];
                    const c = Object.assign({}, root.callbacks);
                    delete c[e.id];
                    root.callbacks = c;
                    if (cb)
                        cb(e.scores ?? {});
                    break;
                }
                case "error":
                    console.warn("[wallpaper] semantic index skipped", e.key, e.error);
                    break;
                }
            }
        }
        onExited: (code, status) => {
            server.up = false;
            root.indexing = false;
            root.forced = false;
            root.callbacks = {};
            if (code !== 0)
                console.warn("[wallpaper] clip.py exited with", code);
            // Something was queued while it shut down: start it again.
            if (root.outbox.length)
                Qt.callLater(() => root.send(root.outbox.pop()));
        }
    }
}
