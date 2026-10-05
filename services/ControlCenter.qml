import QtQuick
import Quickshell
import Quickshell.Io
import "../modules/quicksettings/QsGrid.js" as QsGrid
import "../modules/quicksettings/QsCatalog.js" as QsCatalog
import "../config"

// Quick Settings layout state (iOS Control Center): PAGES (the tabs on the
// module's right rail), each a grid layout of cards; a card lives on at
// most one page. Shared by every island (one layout); the island reads
// `rows` (tallest page — pages slide inside one viewport, no resize per
// swipe), `editing`, `hiddenIds` and `railIcons` to size itself before the
// module renders (QsMetrics). Persisted as state, not config:
// Quickshell.statePath("quicksettings.json") ({ version: 2, pages }), written
// on edit end; a version-1 file ({ items }) loads as one page.
//
// While a card is dragged/resized the module publishes a `preview` (all
// pages; others pushed aside live); commit() makes it the layout. Previews
// always start from `pages` (the layout at drag start), so a long drag
// never accumulates pushes.
Scope {
    id: root
    required property var cfg
    property var haptics: null

    property var pages: [QsCatalog.sanitize(QsCatalog.DEFAULT_LAYOUT)]
    property var preview: null
    property bool editing: false
    // Current tab (session only).
    property int page: 0

    readonly property var shown: root.preview ?? root.pages
    readonly property int rows: root.shown.reduce((m, p) => Math.max(m, QsGrid.rowsOf(p)), 0)
    readonly property var hiddenIds: QsCatalog.IDS.filter(id => root.pageOf(id, root.pages) < 0)
    readonly property bool railShown: root.pages.length > 1 || root.editing
    // Rail icons: one per page + "+" (new tab) in edit mode.
    readonly property int railIcons: root.railShown ? root.pages.length + (root.editing ? 1 : 0) : 0
    readonly property int cols: root.cfg?.cols ?? 4

    function pageOf(id: string, set: var): int {
        return (set ?? root.shown).findIndex(p => p.some(i => i.id === id));
    }
    // { id, x, y, w, h, page } on the shown layout, or null (hidden).
    function rectOf(id: string): var {
        const pg = root.pageOf(id, root.shown);
        if (pg < 0)
            return null;
        const r = root.shown[pg].find(i => i.id === id);
        return { id: r.id, x: r.x, y: r.y, w: r.w, h: r.h, page: pg };
    }
    function itemOf(id: string): var {
        const pg = root.pageOf(id, root.pages);
        return pg < 0 ? null : root.pages[pg].find(i => i.id === id);
    }

    // Haptics (Config.haptics.quickSettings): deep = edit mode entered,
    // click = a dragged card snapped to a new layout,
    // release = tab switched / a resized card snapped to a new size.
    function haptic(effect: string): void {
        if (Config.data.haptics?.quickSettings)
            root.haptics?.play(effect);
    }

    function setPage(p: int): void {
        const next = Math.max(0, Math.min(root.pages.length - 1, p));
        if (next !== root.page)
            root.haptic("release");
        root.page = next;
    }
    function beginEdit(): void {
        if (!root.editing)
            root.haptic("deep");
        root.editing = true;
    }
    function endEdit(): void {
        if (!root.editing)
            return;
        root.preview = null;
        root.editing = false;
        const kept = root.pages.filter(p => p.length > 0);
        const cur = root.pages[root.page];
        root.pages = kept.length > 0 ? kept : [[]];
        root.page = Math.max(0, root.pages.indexOf(cur));
        root.save();
    }

    // Move `id` to cell (x, y) on page `pg` (possibly another page).
    function previewMove(id: string, pg: int, x: int, y: int): void {
        const src = root.pageOf(id, root.pages);
        const it = root.itemOf(id);
        if (src < 0 || pg < 0 || pg >= root.pages.length)
            return;
        const next = root.pages.map(p => QsGrid.clone(p));
        if (src === pg) {
            next[pg] = QsGrid.moveTo(root.pages[pg], root.cols, id, x, y);
        } else {
            next[src] = QsGrid.remove(next[src], id);
            next[pg].push({ id: id, x: x, y: y, w: it.w, h: it.h });
            next[pg] = QsGrid.resolve(next[pg], root.cols, id, null);
        }
        root.setPreview(next, "click");
    }
    function previewResize(id: string, w: int, h: int): void {
        const pg = root.pageOf(id, root.pages);
        if (pg < 0)
            return;
        const next = root.pages.map(p => QsGrid.clone(p));
        next[pg] = QsGrid.resizeTo(root.pages[pg], root.cols, id, w, h);
        root.setPreview(next, "release");
    }
    // effect: click for a move snap, release for a resize step.
    function setPreview(next: var, effect: string): void {
        const cur = root.shown;
        if (next.length !== cur.length || next.some((p, i) => !QsGrid.same(p, cur[i]))) {
            root.preview = next;
            root.haptic(effect);
        }
    }
    function commit(): void {
        if (root.preview)
            root.pages = root.preview.map(p => QsGrid.squeeze(p));
        root.preview = null;
    }

    function add(id: string): void {
        const s = QsCatalog.sizesOf(id)[0];
        const next = root.pages.slice();
        next[root.page] = QsGrid.add(next[root.page], root.cols, id, s[0], s[1]);
        root.pages = next;
    }
    function remove(id: string): void {
        root.pages = root.pages.map(p => QsGrid.squeeze(QsGrid.remove(p, id)));
    }
    // New empty tab (edit mode), switched to.
    function addPage(): void {
        root.pages = root.pages.concat([[]]);
        root.page = root.pages.length - 1;
    }

    function save(): void {
        stateFile.setText(JSON.stringify({ version: 2, pages: root.pages }, null, 2));
    }

    function load(parsed: var): void {
        const raw = parsed.pages ?? [parsed.items ?? []];
        const seen = {};
        // A card may appear once overall: later duplicates are dropped.
        const pages = raw.map(p => QsCatalog.sanitize(p).filter(i => {
            if (seen[i.id])
                return false;
            seen[i.id] = true;
            return true;
        })).map(p => QsGrid.resolve(p, root.cols, "", null));
        root.pages = pages.length > 0 ? pages : [[]];
        root.page = 0;
    }

    // A narrower grid (config cols changed) re-resolves overflowing cards.
    onColsChanged: root.pages = root.pages.map(p => QsGrid.resolve(p, root.cols, "", null))

    FileView {
        id: stateFile
        path: Quickshell.statePath("quicksettings.json")
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                root.load(JSON.parse(stateFile.text()));
            } catch (e) {
                console.warn("ControlCenter: bad state file, using defaults:", e);
            }
        }
    }
}
