import QtQuick
import "../../api"
import "../../../../components"
import "../../../../config"
import "WallFilter.js" as WallFilter
import "CarouselMath.js" as CarouselMath
import "WallKeys.js" as WallKeys
import "WallActions.js" as WallActions

// Wallpaper carousel (pShell Wallpaper Engine look, backend wallr). The
// plugin owns the state — filtered `entries`, `selected`, the animated
// centre `pos` — and WallCarousel only draws it, so the body can be rebuilt
// by the host at any time. Favourites/history/apply live in the shell-wide
// services/Wallpaper (host.wallpaper); keys in WallKeys.js.
//   Pace picks the spring (cfg.speeds): a single step, quick steps within
//   speedWindowMs, auto-repeat / jumps. Search: WallFilter (v/g/i/f/h).
//   Enter = this island's output, Alt+Enter = every output (cfg.effect;
//   "island" grows the new wallpaper out of the bar). Live preview:
//   WallPreview.
LauncherPlugin {
    id: root

    readonly property var c: root.cfg?.wallpapers ?? ({})
    readonly property var wallpaper: root.host?.wallpaper ?? null

    bodyComponent: carouselComp
    bodyWidth: CarouselMath.bodyWidth(root.c)
    bodyHeight: root.c.cardHeight ?? 230

    // Exposed for WallActions.js.
    readonly property alias fileService: wallService
    readonly property alias previewer: preview

    WallpaperService {
        id: wallService
        cfg: root.c
        watching: root.isActive
        onFilesChanged: root.rebuild("", true)
    }

    // Favourites / history filters follow the service live.
    Connections {
        target: root.wallpaper
        function onFavouritesChanged(): void {
            if (root.filter.filter === "fav")
                root.rebuild("", true);
        }
        function onHistoryChanged(): void {
            if (root.filter.filter === "history")
                root.rebuild("", true);
        }
    }

    property var filter: ({ filter: "", query: "" })
    // Hidden files: normal | include | only (Ctrl+H cycles, session only).
    property string visibility: "normal"
    onVisibilityChanged: root.rebuild("", false)
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

    function quietSnap(i: int): void {
        root.quietCentre = true;
        root.snapTo(i);
        root.quietCentre = false;
    }

    // ---- activation / search ----

    function onActivated(initialQuery: string): void {
        preview.reset();
        root.focusPath = "";
        if (root.host?.screen)
            wallService.readCurrent(root.host.screen, path => {
                preview.original = path;
                root.wallpaper?.noteCurrent(path);
                if (!root.focusPath && path) {
                    root.focusPath = path;
                    const i = root.indexOf[path];
                    if (i !== undefined)
                        root.quietSnap(i);
                }
            });
        handleInput(initialQuery ?? "");
    }

    function onDeactivated(): void {
        preview.restore();
    }

    Component.onDestruction: preview.restore()

    function handleInput(q: string): void {
        root.filter = WallFilter.parse(q);
        rebuild("", false);
    }

    // Path to keep in the centre across a rebuild (the selection, or the
    // current wallpaper before anything was picked).
    property string focusPath: ""

    // keep: path to centre ("" = the current selection); sameList: the
    // files/favourites changed under an unchanged query — a vanished
    // selection then keeps its slot instead of jumping to the start.
    function rebuild(keep: string, sameList: bool): void {
        const list = WallFilter.apply(wallService.files, root.filter, {
            favourites: root.wallpaper?.favouriteSet ?? {},
            history: root.wallpaper?.history ?? [],
            visibility: root.visibility
        });
        const idx = {};
        for (let i = 0; i < list.length; i++)
            idx[list[i].path] = i;
        const path = keep || (root.current?.path ?? root.focusPath);
        const fallback = sameList ? Math.max(0, Math.min(root.selected, list.length - 1)) : 0;
        root.entries = list;
        root.indexOf = idx;
        // Filtering re-indexes everything: jump (no flight across the list),
        // the cards rise in on their own.
        root.quietSnap(idx[path] ?? fallback);
        root.wantThumbs();
    }

    // Centre a path, clearing the search if it hides it.
    function focusOn(path: string): void {
        if (root.indexOf[path] !== undefined) {
            root.select(root.indexOf[path]);
            return;
        }
        if (root.filter.filter || root.filter.query) {
            root.requestSetInput("");
            root.filter = WallFilter.parse("");
        }
        root.focusPath = path;
        root.rebuild(path, false);
    }

    function handleKey(e: var): bool {
        return WallKeys.handle(root, e);
    }

    // ---- motion ----

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

    // Wheel / touchpad (WallActions.wheel accumulates into wheelAcc).
    property real wheelAcc: 0
    function wheel(delta: real, unit: real): void {
        WallActions.wheel(root, delta, unit);
    }

    // ---- actions (WallActions.js) ----

    function handleExecute(query: string, isAlt: bool): bool {
        if (root.current)
            root.apply(root.current, isAlt);
        return true;
    }

    function apply(entry: var, allOutputs: bool): void {
        WallActions.apply(root, entry, allOutputs);
    }
    function toggleHidden(): void {
        WallActions.toggleHidden(root);
    }
    function cycleVisibility(): void {
        const v = WallFilter.VISIBILITY;
        root.visibility = v[(v.indexOf(root.visibility) + 1) % v.length];
    }
    function historyStep(dir: int): void {
        WallActions.historyStep(root, dir);
    }
    function randomCard(): void {
        WallActions.randomCard(root);
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
        preview.cancel();
    }
    onSettledChanged: {
        root.playReady = false;
        if (root.settled) {
            root.speedLevel = 0;
            playTimer.restart();
            preview.rest();
        }
    }
    Timer {
        id: playTimer
        interval: root.c.playDelayMs ?? 700
        onTriggered: root.playReady = root.settled
    }

    WallPreview {
        id: preview
        c: root.c
        host: root.host
        active: root.isActive
        target: root.current?.path ?? ""
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
