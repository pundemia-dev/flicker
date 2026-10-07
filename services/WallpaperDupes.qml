import QtQuick
import Quickshell
import Quickshell.Io
import "../modules/launcher/plugins/wallpapers/WallEntry.js" as WallEntry

// Visual duplicate groups for the carousel's "d " view (owned by
// services/Wallpaper): scans the folder, feeds every "key\tpath" to
// scripts/wallpapers/dupes.py (perceptual match on the carousel
// thumbnails — same picture in another resolution / format counts) and
// keeps the result: `groups` (arrays of { path, w, h, bytes }, biggest
// first) + `info` (path → { group, index, count, w, h, bytes }).
// Fingerprints are cached by the script, so a refresh after the first one
// takes ~2 s for ~5000 files. WallpaperWarmup refreshes it after making
// thumbnails, the carousel when the view opens on stale data.
Scope {
    id: root
    property var cfg: ({})
    property string cacheDir: ""

    property var groups: []
    property var info: ({})
    property bool busy: false
    property real updatedAt: 0
    property bool queued: false

    readonly property string scripts: Quickshell.shellDir + "/scripts/wallpapers/"

    // Fresh enough (dupesMaxAgeMin) → nothing to do.
    function ensure(): void {
        if (Date.now() - root.updatedAt > (root.cfg.dupesMaxAgeMin ?? 10) * 60000)
            root.refresh();
    }

    function refresh(): void {
        if (root.busy) {
            root.queued = true;
            return;
        }
        root.busy = true;
        scanProc.command = [root.scripts + "scan.sh", "files", (root.cfg.recursive ?? true) ? "1" : "0"].concat(root.cfg.dirs ?? []);
        scanProc.running = true;
    }

    Process {
        id: scanProc
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = WallEntry.lines(this.text).map(l => WallEntry.make(l.path, l.mtimeText, l.sizeText))
                    .map(e => e.key + "\t" + e.path);
                dupesProc.input = lines.join("\n") + "\n";
                dupesProc.command = ["python3", root.scripts + "dupes.py", root.cacheDir,
                    String(root.cfg.dupesHashDistance ?? 10), String(root.cfg.dupesMaxPixel ?? 48),
                    String(root.cfg.dupesMaxMean ?? 8), String(root.cfg.dupesMaxZ ?? 0.2), String(root.cfg.dupesFlatStd ?? 3)];
                dupesProc.running = true;
            }
        }
        onExited: (code, status) => {
            if (code !== 0)
                root.done();
        }
    }

    Process {
        id: dupesProc
        property string input: ""
        stdinEnabled: true
        onStarted: {
            dupesProc.write(dupesProc.input);
            dupesProc.stdinEnabled = false; // EOF
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(this.text);
                    const info = {};
                    r.groups.forEach((g, gi) => g.forEach((d, i) => {
                        info[d.path] = Object.assign({ group: gi + 1, index: i + 1, count: g.length }, d);
                    }));
                    root.groups = r.groups;
                    root.info = info;
                    root.updatedAt = Date.now();
                    console.info("[wallpaper] duplicates:", r.groups.length, "groups over", r.hashed, "files,", r.missing, "without a thumbnail");
                } catch (e) {
                    console.warn("[wallpaper] dupes.py output unreadable:", e);
                }
            }
        }
        onExited: (code, status) => {
            dupesProc.stdinEnabled = true;
            if (code !== 0)
                console.warn("[wallpaper] dupes.py exited with", code);
            root.done();
        }
    }

    function done(): void {
        root.busy = false;
        if (root.queued) {
            root.queued = false;
            Qt.callLater(root.refresh);
        }
    }
}
