import QtQuick
import Quickshell
import Quickshell.Io
import "../modules/launcher/plugins/wallpapers/WallEntry.js" as WallEntry

// Background thumbnail warm-up for the wallpaper carousel (owned by
// services/Wallpaper): the carousel makes thumbnails only around its
// selection, so fast scrolling through a big folder showed empty cards.
// warmupDelaySec after start (and every warmupRescanMin) it lists the
// folder + the cache and feeds every missing thumbnail to
// scripts/wallpapers/thumbs.sh in batches (warmupBatch files, warmupJobs
// ffmpeg at once, nice 10). Stops on battery unless warmupOnBattery;
// a killed batch is harmless (thumbs.sh writes atomically and the
// carousel's own runs skip files that exist).
Scope {
    id: root
    property var cfg: ({})
    property bool discharging: false

    readonly property string scripts: Quickshell.shellDir + "/scripts/wallpapers/"
    // Same default as the carousel's WallpaperService.cacheDir.
    readonly property string cacheDir: {
        const d = root.cfg.cacheDir ?? "";
        if (d.length)
            return d.replace(/^~/, Quickshell.env("HOME"));
        const x = Quickshell.env("XDG_CACHE_HOME");
        return ((x && x.length) ? x : Quickshell.env("HOME") + "/.cache") + "/flicker/wallpapers";
    }

    readonly property bool allowed: (root.cfg.warmup ?? true) && (!root.discharging || (root.cfg.warmupOnBattery ?? false))
    // Every thumbnail exists (after a scan / the last batch): the duplicate
    // finder can run over a complete set.
    signal idle

    // Flat [key, path, key, path, ...] still to make.
    property var queue: []
    property bool started: false
    // Progress of the current run (StatusFeeds `wallpaperWarmup`).
    property int total: 0
    property int inFlight: 0
    readonly property bool busy: root.allowed && (batch.running || root.queue.length > 0)
    readonly property real progress: root.total > 0 ? Math.max(0, 1 - (root.queue.length / 2 + root.inFlight) / root.total) : 0

    onAllowedChanged: {
        if (!root.allowed)
            batch.running = false;
        else if (root.started)
            Qt.callLater(root.pump);
    }

    Timer {
        interval: (root.cfg.warmupDelaySec ?? 60) * 1000
        running: root.allowed && !root.started
        onTriggered: {
            root.started = true;
            root.scan();
        }
    }
    Timer {
        interval: Math.max(1, root.cfg.warmupRescanMin ?? 30) * 60000
        repeat: true
        running: root.allowed && root.started
        onTriggered: root.scan()
    }

    function scan(): void {
        if (scanProc.running || batch.running)
            return;
        scanProc.command = ["bash", "-c", "mkdir -p \"$1\"; ls -1 \"$1\"; echo ---; shift; \"$@\"", "warmup", root.cacheDir,
            root.scripts + "scan.sh", "files", (root.cfg.recursive ?? true) ? "1" : "0"].concat(root.cfg.dirs ?? []);
        scanProc.running = true;
    }

    Process {
        id: scanProc
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.split("\n---\n");
                const have = {};
                for (const f of (parts[0] ?? "").split("\n"))
                    if (f.endsWith(".jpg") && !f.startsWith("."))
                        have[f.slice(0, -4)] = true;
                const q = [];
                for (const l of WallEntry.lines(parts[1] ?? "")) {
                    const e = WallEntry.make(l.path, l.mtimeText, l.sizeText);
                    if (!have[e.key]) {
                        have[e.key] = true; // hidden + visible twin share a key
                        q.push(e.key, e.path);
                    }
                }
                root.queue = q;
                root.total = q.length / 2;
                if (q.length)
                    console.info("[wallpaper] warm-up:", q.length / 2, "thumbnails to make");
                Qt.callLater(root.pump);
            }
        }
    }

    function pump(): void {
        if (!root.allowed || batch.running)
            return;
        if (!root.queue.length) {
            root.idle();
            return;
        }
        const n = Math.max(1, root.cfg.warmupBatch ?? 40) * 2;
        const args = root.queue.slice(0, n);
        root.queue = root.queue.slice(n);
        root.inFlight = args.length / 2;
        batch.command = [root.scripts + "thumbs.sh", root.cacheDir, String(root.cfg.thumbHeight ?? 460),
            String(Math.max(1, root.cfg.warmupJobs ?? 1))].concat(args);
        batch.running = true;
    }

    Process {
        id: batch
        onExited: {
            root.inFlight = 0;
            Qt.callLater(root.pump);
        }
    }
}
