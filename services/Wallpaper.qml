import QtQuick
import Quickshell
import Quickshell.Io
import "../config"
import "../modules/launcher/plugins/wallpapers/WallrArgs.js" as WallrArgs

// Wallpaper state shared by every island and the launcher carousel
// (backend wallr; tunables Config.launcher.wallpapers):
//   favourites / history — persisted in Quickshell.statePath("wallpapers.json")
//     ({ version: 1, favourites, history }: paths, newest first);
//   apply() — every set goes through here, so it lands in the history;
//   random() — `island wallpaperRandom` (all files or favourites,
//     randomFrom), never the wallpaper already on that output;
//   setHidden() — renames to ".name" and back (hidden files show in the
//     carousel only on request; random never picks them);
//   video pause — `wallr ipc pause/resume -m <output>` while a window is
//     fullscreen there (pauseOnFullscreen) or on battery (pauseOnBattery).
Scope {
    id: root
    required property var compositor
    required property var battery

    readonly property var cfg: Config.data.launcher?.wallpapers ?? ({})
    readonly property string scripts: Quickshell.shellDir + "/scripts/wallpapers/"

    // ---- persisted state ----

    property var favourites: []
    property var history: []
    readonly property var favouriteSet: {
        const s = {};
        for (const p of root.favourites)
            s[p] = true;
        return s;
    }

    function isFavourite(path: string): bool {
        return !!root.favouriteSet[path];
    }

    function setFavourite(path: string, on: bool): void {
        if (!path || root.isFavourite(path) === on)
            return;
        root.favourites = on ? [path].concat(root.favourites) : root.favourites.filter(p => p !== path);
        root.save();
    }

    function toggleFavourite(path: string): void {
        root.setFavourite(path, !root.isFavourite(path));
    }

    function pushHistory(path: string): void {
        if (!path || root.history[0] === path)
            return;
        root.history = [path].concat(root.history.filter(p => p !== path)).slice(0, Math.max(1, root.cfg.historyLimit ?? 100));
        root.save();
    }

    // The wallpaper already on screen when the carousel opens (set before
    // the history existed, or by wallr's own restore) heads the history, so
    // "back" starts from it.
    function noteCurrent(path: string): void {
        root.pushHistory(path);
    }

    function save(): void {
        stateFile.setText(JSON.stringify({ version: 1, favourites: root.favourites, history: root.history }, null, 2));
    }

    FileView {
        id: stateFile
        path: Quickshell.statePath("wallpapers.json")
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(stateFile.text());
                root.favourites = (s.favourites ?? []).filter(p => typeof p === "string");
                root.history = (s.history ?? []).filter(p => typeof p === "string");
            } catch (e) {
                console.warn("Wallpaper: bad state file, starting empty:", e);
            }
        }
    }

    // ---- set ----

    // Bar centre of an output, normalized (y from the top): the "island"
    // effect grows from there.
    function originFor(output: string): var {
        const s = Quickshell.screens.find(x => x.name === output);
        const isl = Config.data.island ?? {};
        return {
            originX: 0.5,
            originY: ((isl.topMargin ?? 10) + (isl.height ?? 36) / 2) / Math.max(1, s?.height ?? 1080)
        };
    }

    // opts: see WallrArgs.set (output "" = all outputs).
    function apply(path: string, opts: var): void {
        Quickshell.execDetached(WallrArgs.set(path, opts, root.cfg.mode ?? ""));
        root.pushHistory(path);
    }

    // Configured effect/duration/theme for a real (non-preview) set.
    function applyOpts(output: string): var {
        return Object.assign({
            output: output,
            effect: root.cfg.effect ?? "island",
            durationMs: root.cfg.durationMs ?? 1000,
            theme: root.cfg.theme ?? ""
        }, root.originFor(output));
    }

    // ---- random ----

    property string randomOutput: ""
    property bool randomQueued: false

    function random(output: string): void {
        root.randomOutput = output ?? "";
        if (randomScan.running) {
            root.randomQueued = true;
            return;
        }
        randomScan.command = [root.scripts + "scan.sh", "files", (root.cfg.recursive ?? true) ? "1" : "0"].concat(root.cfg.dirs ?? []);
        randomScan.running = true;
    }

    Process {
        id: randomScan
        stdout: StdioCollector {
            onStreamFinished: root.pickRandom(this.text)
        }
        onExited: if (root.randomQueued) {
            root.randomQueued = false;
            root.random(root.randomOutput);
        }
    }

    function pickRandom(text: string): void {
        if (root.randomQueued)
            return; // a newer request rescans anyway
        const files = text.split("\n").map(l => l.split("\t").slice(2).join("\t"))
            .filter(p => p.length && !root.isHiddenPath(p));
        let pool = files;
        if ((root.cfg.randomFrom ?? "all") === "favourites") {
            const have = new Set(files);
            const favs = root.favourites.filter(p => have.has(p));
            if (favs.length)
                pool = favs;
        }
        const current = root.history[0] ?? "";
        if (pool.length > 1)
            pool = pool.filter(p => p !== current);
        if (!pool.length)
            return;
        root.apply(pool[Math.floor(Math.random() * pool.length)], root.applyOpts(root.randomOutput));
    }

    // ---- hide / unhide ----

    function isHiddenPath(path: string): bool {
        return path.slice(path.lastIndexOf("/") + 1).startsWith(".");
    }

    // Renames "name" <-> ".name" (mv -n: never overwrites); returns the new
    // path. Hiding drops the file from favourites/history (paths change).
    function setHidden(path: string, hide: bool): string {
        if (!path || root.isHiddenPath(path) === hide)
            return path;
        const slash = path.lastIndexOf("/");
        const base = path.slice(slash + 1);
        const dest = path.slice(0, slash + 1) + (hide ? "." + base : base.slice(1));
        Quickshell.execDetached(["mv", "-n", "--", path, dest]);
        if (hide) {
            root.favourites = root.favourites.filter(p => p !== path);
            root.history = root.history.filter(p => p !== path);
            root.save();
        }
        return dest;
    }

    // ---- video pause (fullscreen / battery) ----

    readonly property bool onBattery: !!root.battery?.present && !root.battery?.charging

    function setPaused(output: string, paused: bool): void {
        Quickshell.execDetached(["wallr", "ipc", paused ? "pause" : "resume", "-m", output]);
    }

    Variants {
        model: Quickshell.screens

        delegate: QtObject {
            required property ShellScreen modelData
            readonly property bool shouldPause: ((root.cfg.pauseOnFullscreen ?? true) && (root.compositor?.fullscreenOn(modelData.name) ?? false))
                || ((root.cfg.pauseOnBattery ?? false) && root.onBattery)
            onShouldPauseChanged: root.setPaused(modelData.name, shouldPause)
            // Start from a known state (a shell restart may have left it paused).
            Component.onCompleted: root.setPaused(modelData.name, shouldPause)
        }
    }
}
