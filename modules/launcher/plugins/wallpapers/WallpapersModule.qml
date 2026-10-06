import QtQuick
import Quickshell
import "../../api"
import "../../../../components"
import "../../../../config"
import "../../fuzzysort.js" as Fuzzy
import "WallrArgs.js" as WallrArgs
import "CarouselMath.js" as CarouselMath

// Wallpaper carousel (pShell Wallpaper Engine look, backend wallr). The
// plugin owns the state — filtered `entries`, `selected`, the animated
// centre `pos` — and WallCarousel only draws it, so the body can be rebuilt
// by the host at any time.
//   ←/→ (↑/↓, Tab) step, Shift+arrows / PgUp/PgDn jump pageStep, Home/End;
//   wheel steps. Pace picks the spring (cfg.speeds): a single step, quick
//   steps within speedWindowMs, auto-repeat / jumps.
//   Query prefixes: "v " videos, "g " GIFs, "i " images; the rest is fuzzy
//   matched on the file name.
//   Enter = this island's output, Alt+Enter = every output (cfg.effect;
//   "island" grows the new wallpaper out of the bar).
//   Live preview (cfg.livePreview): once the carousel rests, the centre
//   card goes onto this output (fade, no theming); leaving without Enter
//   (Esc, closing, another plugin) puts the original back.
LauncherPlugin {
    id: root

    readonly property var c: root.cfg?.wallpapers ?? ({})

    bodyComponent: carouselComp
    bodyWidth: CarouselMath.bodyWidth(root.c)
    bodyHeight: root.c.cardHeight ?? 230

    WallpaperService {
        id: wallService
        cfg: root.c
        watching: root.isActive
        onFilesChanged: root.rebuild()
    }

    property string query: ""
    property string typeFilter: ""
    property var entries: []
    // path -> index in entries (reassigned on rebuild: delegates bind it).
    property var indexOf: ({})
    property int selected: 0
    readonly property var current: root.entries[root.selected] ?? null

    // Animated centre, in cards (WallCard offset d = index - pos).
    property real pos: 0
    property int speedLevel: 0
    readonly property var speed: (root.c.speeds ?? [])[root.speedLevel] ?? ({ stiffness: 4, damping: 0.45 })
    Behavior on pos {
        id: posBehavior
        Spring {
            stiffness: root.speed.stiffness
            damp: root.speed.damping
            eps: 0.002
        }
    }
    // "At rest" for play/preview: within settleEps of the target — the
    // spring's tail is long and invisible, waiting for it added ~0.3 s.
    readonly property bool settled: Math.abs(root.pos - root.selected) < (root.c.settleEps ?? 0.05)

    // Haptic detent: a click each time a card passes the centre (a jump
    // clicks once; a rebuild after typing is silent). Config.haptics.wallpapers.
    readonly property int centreIndex: Math.round(root.pos)
    property bool quietCentre: false
    onCentreIndexChanged: if (!root.quietCentre && root.isActive && (Config.data.haptics?.wallpapers ?? true))
        root.host?.haptics?.click()

    function snapTo(i: int): void {
        posBehavior.enabled = false;
        root.selected = i;
        root.pos = i;
        posBehavior.enabled = true;
    }

    // ---- input ----

    function onActivated(initialQuery: string): void {
        root.applied = false;
        root.previewed = "";
        root.original = "";
        root.focusPath = "";
        if (root.host?.screen)
            wallService.readCurrent(root.host.screen, path => {
                root.original = path;
                if (!root.focusPath && path) {
                    root.focusPath = path;
                    const i = root.indexOf[path];
                    if (i !== undefined) {
                        root.quietCentre = true;
                        root.snapTo(i);
                        root.quietCentre = false;
                    }
                }
            });
        handleInput(initialQuery ?? "");
    }

    function onDeactivated(): void {
        root.restoreOriginal();
    }

    Component.onDestruction: root.restoreOriginal()

    function handleInput(q: string): void {
        const m = /^([vgi])(?:\s+|$)(.*)$/.exec(q ?? "");
        root.typeFilter = m ? ({ v: "video", g: "gif", i: "image" })[m[1]] : "";
        root.query = (m ? m[2] : q ?? "").trim();
        rebuild();
    }

    // Path to keep in the centre across a rebuild (the selection, or the
    // current wallpaper before anything was picked).
    property string focusPath: ""

    function rebuild(): void {
        let list = wallService.files;
        if (root.typeFilter)
            list = list.filter(e => e.type === root.typeFilter);
        if (root.query)
            list = Fuzzy.go(root.query, list, { key: "name" }).map(r => r.obj);
        const idx = {};
        for (let i = 0; i < list.length; i++)
            idx[list[i].path] = i;
        const keep = root.current?.path ?? root.focusPath;
        root.entries = list;
        root.indexOf = idx;
        // Filtering re-indexes everything: jump (no flight across the list),
        // the cards rise in on their own.
        root.quietCentre = true;
        root.snapTo(idx[keep] ?? 0);
        root.quietCentre = false;
        root.wantThumbs();
    }

    function handleKey(e: var): bool {
        const shift = (e.modifiers & Qt.ShiftModifier) !== 0;
        const page = root.c.pageStep ?? 5;
        switch (e.key) {
        case Qt.Key_Left:
        case Qt.Key_Up:
        case Qt.Key_Backtab:
            root.step(shift ? -page : -1, e.isAutoRepeat);
            return true;
        case Qt.Key_Right:
        case Qt.Key_Down:
        case Qt.Key_Tab:
            root.step(shift ? page : 1, e.isAutoRepeat);
            return true;
        case Qt.Key_PageUp:
            root.step(-page, true);
            return true;
        case Qt.Key_PageDown:
            root.step(page, true);
            return true;
        case Qt.Key_Home:
            root.step(-root.selected, true);
            return true;
        case Qt.Key_End:
            root.step(root.entries.length - 1 - root.selected, true);
            return true;
        }
        return false;
    }

    property real lastStepAt: 0

    // n cards; `fast` = auto-repeat or a jump → the fastest spring.
    function step(n: int, fast: bool): void {
        if (!root.entries.length || n === 0)
            return;
        const now = Date.now();
        const quick = now - root.lastStepAt < (root.c.speedWindowMs ?? 280);
        root.lastStepAt = now;
        const top = Math.max(0, (root.c.speeds ?? []).length - 1);
        root.speedLevel = Math.min(top, fast || Math.abs(n) > 1 ? 2 : (quick ? Math.max(1, root.speedLevel) : 0));
        const i = Math.max(0, Math.min(root.entries.length - 1, root.selected + n));
        // A far jump (Home/End over thousands) cuts instead of flying past
        // every card; the cards rise in around the new centre.
        if (Math.abs(i - root.pos) > (root.c.flyMax ?? 30)) {
            root.snapTo(i);
        } else {
            root.selected = i;
            root.pos = i; // the Behavior springs it there
        }
        root.focusPath = root.entries[i]?.path ?? "";
        root.wantThumbs();
    }

    function select(i: int): void {
        root.step(i - root.selected, Math.abs(i - root.selected) > 1);
    }

    // Wheel / touchpad: one card per `unit` of angle delta (a mouse notch
    // = 120; touchpads deliver small deltas that accumulate).
    property real wheelAcc: 0
    function wheel(delta: real, unit: real): void {
        // Touchpads interleave zero-delta events (the other axis): skip
        // them, they must not count as a direction change.
        if (delta === 0)
            return;
        if (root.wheelAcc !== 0 && Math.sign(delta) !== Math.sign(root.wheelAcc))
            root.wheelAcc = 0; // direction change: no leftover from the last swipe
        root.wheelAcc += delta;
        while (Math.abs(root.wheelAcc) >= unit) {
            // Positive = wheel up / content pulled right = previous card.
            const back = root.wheelAcc > 0;
            root.wheelAcc += back ? -unit : unit;
            root.step(back ? -1 : 1, false);
        }
    }

    function handleExecute(query: string, isAlt: bool): bool {
        if (root.current)
            root.apply(root.current, isAlt);
        return true;
    }

    // ---- thumbnails: the cards around the centre, nearest first ----

    function wantThumbs(): void {
        const n = root.entries.length;
        if (!n)
            return;
        const reach = root.c.thumbAhead ?? 8;
        const out = [];
        for (let k = 0; k <= reach; k++) {
            if (root.selected + k < n)
                out.push(root.entries[root.selected + k]);
            if (k > 0 && root.selected - k >= 0)
                out.push(root.entries[root.selected - k]);
        }
        wallService.want(out);
    }

    // ---- live media + preview once the carousel rests ----

    property bool playReady: false
    readonly property bool playing: root.settled && root.playReady
    onSelectedChanged: {
        root.playReady = false;
        previewTimer.stop();
    }
    onSettledChanged: {
        root.playReady = false;
        if (root.settled) {
            root.speedLevel = 0;
            playTimer.restart();
            previewTimer.restart();
        }
    }
    Timer {
        id: playTimer
        interval: root.c.playDelayMs ?? 700
        onTriggered: root.playReady = root.settled
    }

    property bool applied: false
    property string original: ""
    // Path last put on the desktop by the preview ("" = untouched).
    property string previewed: ""

    Timer {
        id: previewTimer
        interval: root.c.previewDelayMs ?? 500
        onTriggered: {
            const e = root.current;
            if (!(root.c.livePreview ?? false) || !root.isActive || !e || !root.host?.screen)
                return;
            if (e.path === (root.previewed || root.original))
                return;
            root.previewed = e.path;
            wallService.set(e.path, root.previewOpts());
        }
    }

    function previewOpts(): var {
        return {
            output: root.host?.screen ?? "",
            effect: "fade",
            durationMs: root.c.previewDurationMs ?? 300,
            theme: "none"
        };
    }

    function restoreOriginal(): void {
        if (root.applied || !root.previewed || !root.original)
            return;
        // Detached + no service call: this also runs from onDestruction.
        if (root.previewed !== root.original)
            Quickshell.execDetached(WallrArgs.set(root.original, root.previewOpts(), root.c.mode ?? ""));
        root.previewed = "";
    }

    function apply(entry: var, allOutputs: bool): void {
        root.applied = true;
        previewTimer.stop();
        wallService.set(entry.path, {
            output: allOutputs ? "" : (root.host?.screen ?? ""),
            effect: root.c.effect ?? "island",
            durationMs: root.c.durationMs ?? 1000,
            originX: root.host?.originX ?? 0.5,
            originY: root.host?.originY ?? 0.03,
            theme: root.c.theme ?? ""
        });
        root.requestClose(true);
    }

    Component {
        id: carouselComp
        WallCarousel {
            plugin: root
            service: wallService
            theme: root.theme
            c: root.c
            lc: root.cfg
        }
    }
}
