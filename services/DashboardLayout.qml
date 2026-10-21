import QtQuick
import Quickshell
import Quickshell.Io
import "../modules/quicksettings/QsGrid.js" as QsGrid
import "../modules/dashboard/DashCatalog.js" as DashCatalog
import "../config"

// Dashboard layout state: one grid of cards (cols fixed by
// Config.dashboard.cols, rows grow with the cards), edited like Quick
// Settings (services/ControlCenter, same QsGrid engine, no tabs). Shared by
// every island; the island reads `rows`, `editing` and `hiddenIds` to size
// itself before the module renders (DashMetrics). Persisted as state, not
// config: Quickshell.statePath("dashboard.json") ({ version: 1, items }),
// written on edit end.
//
// While a card is dragged/resized the module publishes a `preview` (others
// pushed aside live); commit() makes it the layout. Previews always start
// from `items` (the layout at drag start), so a long drag never accumulates
// pushes.
Scope {
    id: root
    required property var cfg
    property var haptics: null

    property var items: DashCatalog.sanitize(DashCatalog.DEFAULT_LAYOUT)
    property var preview: null
    property bool editing: false

    readonly property var shown: root.preview ?? root.items
    readonly property int rows: QsGrid.rowsOf(root.shown)
    readonly property var hiddenIds: DashCatalog.IDS.filter(id => !root.items.some(i => i.id === id))
    readonly property int cols: root.cfg?.cols ?? 8

    // { id, x, y, w, h } on the shown layout, or null (hidden).
    function rectOf(id: string): var {
        return root.shown.find(i => i.id === id) ?? null;
    }
    function itemOf(id: string): var {
        return root.items.find(i => i.id === id) ?? null;
    }

    // Haptics (Config.haptics.dashboard): deep = edit mode entered, click =
    // a dragged card snapped to a new layout, release = a resized card
    // snapped to a new size.
    function haptic(effect: string): void {
        if (Config.data.haptics?.dashboard)
            root.haptics?.play(effect);
    }

    function beginEdit(): void {
        if (!root.editing)
            root.haptic("deep");
        root.editing = true;
    }
    function endEdit(): void {
        if (!root.editing)
            return;
        root.commit();
        root.editing = false;
        root.save();
    }

    function previewMove(id: string, x: int, y: int): void {
        if (root.itemOf(id))
            root.setPreview(QsGrid.moveTo(root.items, root.cols, id, x, y), "click");
    }
    function previewResize(id: string, w: int, h: int): void {
        if (root.itemOf(id))
            root.setPreview(QsGrid.resizeTo(root.items, root.cols, id, w, h), "release");
    }
    function setPreview(next: var, effect: string): void {
        if (!QsGrid.same(next, root.shown)) {
            root.preview = next;
            root.haptic(effect);
        }
    }
    function commit(): void {
        if (root.preview)
            root.items = QsGrid.squeeze(root.preview);
        root.preview = null;
    }

    function add(id: string): void {
        const s = DashCatalog.sizesOf(id)[0];
        root.items = QsGrid.add(root.items, root.cols, id, s[0], s[1]);
    }
    function remove(id: string): void {
        root.items = QsGrid.squeeze(QsGrid.remove(root.items, id));
    }

    function save(): void {
        stateFile.setText(JSON.stringify({ version: 1, items: root.items }, null, 2));
    }

    // A narrower grid (config cols changed) re-resolves overflowing cards.
    onColsChanged: if (root.items) root.items = QsGrid.resolve(root.items, root.cols, "", null)

    FileView {
        id: stateFile
        path: Quickshell.statePath("dashboard.json")
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                root.items = QsGrid.resolve(DashCatalog.sanitize(JSON.parse(stateFile.text()).items), root.cols, "", null);
            } catch (e) {
                console.warn("DashboardLayout: bad state file, using defaults:", e);
            }
        }
    }
}
