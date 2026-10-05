import QtQuick
import Quickshell
import Quickshell.Io
import "../modules/quicksettings/QsGrid.js" as QsGrid
import "../modules/quicksettings/QsCatalog.js" as QsCatalog

// Quick Settings layout state (iOS Control Center): which cards are on
// the grid, where and how big. Shared by every island (one layout); the
// island reads `rows`/`editing`/`hiddenIds` to size itself before the
// module renders (QsMetrics). Persisted as state, not config:
// Quickshell.statePath("quicksettings.json"), written on edit end.
//
// While a card is dragged/resized the module publishes a `preview` layout
// (others pushed aside live); commit() makes it the layout. Previews are
// always computed from `items` (the layout at drag start), so a long drag
// never accumulates pushes.
Scope {
    id: root
    required property var cfg

    property var items: QsCatalog.sanitize(QsCatalog.DEFAULT_LAYOUT)
    property var preview: null
    property bool editing: false

    readonly property var shown: root.preview ?? root.items
    readonly property int rows: QsGrid.rowsOf(root.shown)
    readonly property var hiddenIds: QsCatalog.IDS.filter(id => !root.items.some(i => i.id === id))
    readonly property int cols: root.cfg?.cols ?? 4

    function rectOf(id: string): var {
        return root.shown.find(i => i.id === id) ?? null;
    }

    function beginEdit(): void {
        root.editing = true;
    }
    function endEdit(): void {
        if (!root.editing)
            return;
        root.preview = null;
        root.editing = false;
        root.save();
    }

    function previewMove(id: string, x: int, y: int): void {
        const next = QsGrid.moveTo(root.items, root.cols, id, x, y);
        if (!QsGrid.same(next, root.shown))
            root.preview = next;
    }
    function previewResize(id: string, w: int, h: int): void {
        const next = QsGrid.resizeTo(root.items, root.cols, id, w, h);
        if (!QsGrid.same(next, root.shown))
            root.preview = next;
    }
    function commit(): void {
        if (root.preview)
            root.items = QsGrid.squeeze(root.preview);
        root.preview = null;
    }
    function cancelPreview(): void {
        root.preview = null;
    }

    function add(id: string): void {
        const s = QsCatalog.sizesOf(id)[0];
        root.items = QsGrid.add(root.items, root.cols, id, s[0], s[1]);
    }
    function remove(id: string): void {
        root.items = QsGrid.squeeze(QsGrid.remove(root.items, id));
    }

    function save(): void {
        stateFile.setText(JSON.stringify({ version: 1, items: root.items }, null, 2));
    }

    // A narrower grid (config cols changed) re-resolves overflowing cards.
    onColsChanged: root.items = QsGrid.resolve(root.items, root.cols, "", null)

    FileView {
        id: stateFile
        path: Quickshell.statePath("quicksettings.json")
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const parsed = JSON.parse(stateFile.text());
                root.items = QsGrid.resolve(QsCatalog.sanitize(parsed.items), root.cols, "", null);
            } catch (e) {
                console.warn("ControlCenter: bad state file, using defaults:", e);
            }
        }
    }
}
