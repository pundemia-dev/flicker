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
//     fullscreen there (pauseOnFullscreen), on battery (pauseOnBattery) or
//     while the session is locked (wallr's video loop dies under a lock);
//   slideshow (WallpaperSlideshow) and the thumbnail warm-up
//     (WallpaperWarmup) live in their own files.
Scope {
    id: root
    required property var compositor
    required property var battery
    // LockScope (Shell): video playback is paused while the session is locked.
    property var lock: null
    // services/Theme: wallAccent is set from the wallpaper (accentFromWallpaper).
    property var theme: null

    // Tunables: config.json (launcher.wallpapers) + the carousel settings
    // panel's overrides (persisted here, never written into config.json).
    property var overrides: ({})
    readonly property var cfg: Object.assign({}, Config.data.launcher?.wallpapers ?? {}, root.overrides)

    function setSetting(key: string, value: var): void {
        const o = Object.assign({}, root.overrides);
        o[key] = value;
        root.overrides = o;
        root.save();
    }

    // Back to config.json for every key the panel changed.
    function resetSettings(): void {
        root.overrides = {};
        root.save();
    }
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
        stateFile.setText(JSON.stringify({
            version: 1,
            favourites: root.favourites,
            history: root.history,
            slideshow: { active: slideshowItem.active, spec: slideshowItem.spec },
            settings: root.overrides
        }, null, 2));
    }

    // Slideshow (services/WallpaperSlideshow): carousel Ctrl+S, IPC
    // wallpaperSlideshow / wallpaperNext.
    readonly property alias slideshow: slideshowItem
    WallpaperSlideshow {
        id: slideshowItem
        wallpaper: root
        cfg: root.cfg
        discharging: root.discharging
        onEdited: root.save()
    }

    // Background thumbnails for the carousel (services/WallpaperWarmup);
    // once they are all there the duplicate groups are refreshed.
    WallpaperWarmup {
        id: warmup
        cfg: root.cfg
        discharging: root.discharging
        onIdle: {
            dupesItem.refresh();
            semanticItem.indexAll();
        }
    }

    readonly property string thumbCacheDir: warmup.cacheDir

    // Text / picture search (services/WallpaperSemantic) for the "? " and
    // "~ " views.
    readonly property alias semantic: semanticItem
    WallpaperSemantic {
        id: semanticItem
        cfg: root.cfg
        discharging: root.discharging
        cacheDir: warmup.cacheDir
    }

    // Visual duplicate groups (services/WallpaperDupes) for the "d " view.
    readonly property alias dupes: dupesItem
    WallpaperDupes {
        id: dupesItem
        cfg: root.cfg
        cacheDir: warmup.cacheDir
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
                root.overrides = (s.settings && typeof s.settings === "object") ? s.settings : {};
                if (s.slideshow?.active)
                    Qt.callLater(() => slideshowItem.start(s.slideshow.spec));
            } catch (e) {
                console.warn("Wallpaper: bad state file, starting empty:", e);
            }
        }
    }

    // ---- set ----

    // Bar centre of an output, normalized (y from the top): the "island"
    // effect grows from there.
    function originFor(output: string): var {
        // "" (every output): the first screen's proportions.
        const s = Quickshell.screens.find(x => x.name === output) ?? Quickshell.screens[0];
        const isl = Config.data.island ?? {};
        return {
            originX: 0.5,
            originY: ((isl.topMargin ?? 10) + (isl.height ?? 36) / 2) / Math.max(1, s?.height ?? 1080)
        };
    }

    // opts: see WallrArgs.set (output "" = all outputs).
    function apply(path: string, opts: var): void {
        root.setOn(path, opts);
        root.pushHistory(path);
        root.updateAccent(path);
    }

    // ---- accent from the wallpaper ----

    // matugen (dark, prefer saturation) on a still image; GIF/video keep
    // the previous accent. Off → the Theme's stock blues.
    function updateAccent(path: string): void {
        if (!(root.cfg.accentFromWallpaper ?? true)) {
            if (root.theme)
                root.theme.wallAccent = "transparent";
            return;
        }
        if (!path || /\.(gif|mp4|webm|mkv|mov)$/i.test(path))
            return;
        if (accentProc.running) {
            accentProc.pending = path;
            return;
        }
        accentProc.command = ["matugen", "image", path, "--json", "hex", "--dry-run", "--prefer", "saturation", "-m", "dark"];
        accentProc.running = true;
    }

    onCfgChanged: Qt.callLater(root.accentFromCurrent)
    Component.onCompleted: root.accentFromCurrent()

    function accentFromCurrent(): void {
        if (!(root.cfg.accentFromWallpaper ?? true)) {
            root.updateAccent("");
            return;
        }
        const out = Quickshell.screens[0]?.name ?? "";
        if (!out || currentProc.running)
            return;
        currentProc.command = [root.scripts + "current.sh", out];
        currentProc.running = true;
    }

    Process {
        id: currentProc
        stdout: StdioCollector {
            onStreamFinished: root.updateAccent(this.text.trim())
        }
    }

    Process {
        id: accentProc
        property string pending: ""
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const tone = String(root.cfg.accentTone ?? 50);
                    const c = JSON.parse(this.text).palettes.primary[tone].color;
                    if (root.theme && c)
                        root.theme.wallAccent = c;
                } catch (e) {
                    console.warn("[wallpaper] matugen accent failed:", e);
                }
            }
        }
        onExited: if (accentProc.pending) {
            const p = accentProc.pending;
            accentProc.pending = "";
            Qt.callLater(() => root.updateAccent(p));
        }
    }

    // Every wallr set goes through scripts/wallpapers/setwall.sh, one per
    // output (pixel size differs): adaptive fill-blur for still images whose
    // aspect is far from the output's (fillBlur*, only with mode "fill").
    // No history: the live preview and its restore use this directly.
    function setOn(path: string, opts: var): void {
        const outs = opts.output ? [opts.output] : Quickshell.screens.map(s => s.name);
        const fill = (root.cfg.fillBlur ?? true) && (root.cfg.mode ?? "fill") === "fill";
        for (const name of outs) {
            const s = Quickshell.screens.find(x => x.name === name);
            const o = Object.assign({}, opts, { output: name });
            if (opts.effect === "island" && !opts.output)
                Object.assign(o, root.originFor(name));
            const rest = WallrArgs.set(path, o, root.cfg.mode ?? "").slice(3);
            const dpr = s?.devicePixelRatio ?? 1;
            Quickshell.execDetached([root.scripts + "setwall.sh", path,
                String(Math.round((s?.width ?? 0) * dpr)), String(Math.round((s?.height ?? 0) * dpr)),
                String(fill ? (root.cfg.fillBlurThreshold ?? 0.8) : 0), String(root.cfg.fillBlurSigma ?? 8),
                String(root.cfg.fillBlurDim ?? 0.25), root.thumbCacheDir, "--"].concat(rest));
        }
    }

    // Configured effect/duration/theme for a real (non-preview) set.
    function applyOpts(output: string): var {
        return Object.assign({
            output: output,
            effect: root.cfg.effect ?? "island",
            durationMs: root.cfg.durationMs ?? 1000,
            theme: root.cfg.theme ?? "",
            params: WallrArgs.params(root.cfg)
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

    // Renames "name" <-> ".name" through scripts/wallpapers/hide.sh (never
    // overwrites: an identical twin under the new name sends the source to
    // the trash, a different one gets "<stem>-<n>"). Returns the EXPECTED
    // path at once (the carousel shows it optimistically); hideDone reports
    // what really happened — the user's folder had 53 "name" + ".name"
    // twins, where a plain `mv -n` silently did nothing and the card came
    // back on the next rescan. Runs one at a time (rapid Ctrl+Shift+H).
    signal hideDone(string from, string to, bool ok)

    function setHidden(path: string, hide: bool): string {
        if (!path || root.isHiddenPath(path) === hide)
            return path;
        const slash = path.lastIndexOf("/");
        const base = path.slice(slash + 1);
        const dest = path.slice(0, slash + 1) + (hide ? "." + base : base.slice(1));
        root.hideQueue = root.hideQueue.concat([[path, dest]]);
        Qt.callLater(root.pumpHide);
        if (hide) {
            root.favourites = root.favourites.filter(p => p !== path);
            root.history = root.history.filter(p => p !== path);
            root.save();
        }
        return dest;
    }

    property var hideQueue: []

    // Ctrl+Delete in the carousel: the file goes to the trash (`gio trash`,
    // restorable from the desktop trash), out of favourites/history.
    signal trashDone(string path, bool ok)

    function trash(path: string): void {
        if (!path)
            return;
        root.favourites = root.favourites.filter(p => p !== path);
        root.history = root.history.filter(p => p !== path);
        root.save();
        root.trashQueue = root.trashQueue.concat([path]);
        Qt.callLater(root.pumpTrash);
    }

    property var trashQueue: []

    function pumpTrash(): void {
        if (trashProc.running || !root.trashQueue.length)
            return;
        trashProc.path = root.trashQueue[0];
        root.trashQueue = root.trashQueue.slice(1);
        trashProc.command = ["gio", "trash", "--", trashProc.path];
        trashProc.running = true;
    }

    Process {
        id: trashProc
        property string path: ""
        onExited: (code, status) => {
            if (code !== 0)
                console.warn("[wallpaper] trash failed:", trashProc.path, code);
            root.trashDone(trashProc.path, code === 0);
            Qt.callLater(root.pumpTrash);
        }
    }

    function pumpHide(): void {
        if (hideProc.running || !root.hideQueue.length)
            return;
        const job = root.hideQueue[0];
        root.hideQueue = root.hideQueue.slice(1);
        hideProc.job = job;
        hideProc.command = [root.scripts + "hide.sh", job[0], job[1]];
        hideProc.running = true;
    }

    Process {
        id: hideProc
        property var job: null
        stdout: StdioCollector {
            onStreamFinished: {
                const out = this.text.trim();
                const ok = out.length > 0 && !out.startsWith("!");
                if (!ok)
                    console.warn("[wallpaper] hide/unhide failed:", hideProc.job?.[0], out);
                root.hideDone(hideProc.job?.[0] ?? "", ok ? out : "", ok);
            }
        }
        onExited: Qt.callLater(root.pumpHide)
    }

    // ---- video pause (fullscreen / battery) ----

    readonly property bool discharging: !!root.battery?.present && !root.battery?.charging

    // wallr 0.6.4 bug (measured: 4 s pause → resume plays, 7 s → dead): its
    // video loop does not refresh "last uploaded frame" while paused, so the
    // first resumed iteration without a ready frame sees > 5 s and stops
    // playback for good ("Video playback stalled"); `resume` / `reload`
    // can't revive it, only a new `set` — and a set of the SAME path with
    // the SAME effect is an idempotent no-op in wallr, hence two instant
    // sets with different effects (wipe, then fade). So a pause longer than
    // `wallrStallMs` ends with the same video set again (no transition, no
    // theme run; it restarts from its first frame). GIFs have no such check.
    property var pausedAt: ({})
    function setPaused(output: string, paused: bool): void {
        if (paused) {
            root.pausedAt[output] = Date.now();
            Quickshell.execDetached(["wallr", "ipc", "pause", "-m", output]);
            return;
        }
        const since = root.pausedAt[output];
        delete root.pausedAt[output];
        if (since !== undefined && Date.now() - since > (root.cfg.wallrStallMs ?? 4000))
            root.revive(output);
        else
            Quickshell.execDetached(["wallr", "ipc", "resume", "-m", output]);
    }
    function revive(output: string): void {
        Quickshell.execDetached(["bash", "-c",
            'p=$(cat "$HOME/.cache/wallr/last_wallpaper/$1" 2>/dev/null); case "${p,,}" in '
            + '*.mp4|*.webm|*.mkv|*.mov|*.avi|*.m4v) wallr set "$p" -m "$1" -e wipe -d 0ms --no-theme; '
            + 'wallr set "$p" -m "$1" -e fade -d 0ms --no-theme ;; '
            + '*) wallr ipc resume -m "$1" ;; esac', "_", output]);
    }

    Variants {
        model: Quickshell.screens

        delegate: QtObject {
            required property ShellScreen modelData
            // Locked: wallr presents with Vulkan FIFO and ignores frame
            // callbacks; under a session lock its surface is never shown, the
            // present blocks, and after 5 s without an uploaded frame its
            // playback loop gives up for good ("Video playback stalled,
            // stopping" — frozen until `wallr ipc reload`, seen after a
            // lock). A pause takes its idle branch instead (no 5 s check).
            readonly property bool shouldPause: ((root.cfg.pauseOnFullscreen ?? true) && (root.compositor?.fullscreenOn(modelData.name) ?? false))
                || ((root.cfg.pauseOnBattery ?? false) && root.discharging)
                || (root.lock?.locked ?? false)
            onShouldPauseChanged: root.setPaused(modelData.name, shouldPause)
            // Start from a known state (a shell restart may have left it paused).
            Component.onCompleted: root.setPaused(modelData.name, shouldPause)
        }
    }
}
