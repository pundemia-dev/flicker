import QtQuick
import Quickshell
import "../../api"
import "../../../../config"

// Calculator plugin: the result card (LauncherManager's shared
// calc/Calculator, always shown here) over the history of copied results.
// History row: Enter copies its answer, Alt+Enter puts the expression back
// into the field, Shift+Delete forgets it. Plain typing in the default
// plugin gets the same card without the history.
LauncherPlugin {
    id: root

    property string query: ""
    property var selectedItem: null

    ScriptModel {
        id: model
    }
    listModel: model

    property var entryCache: new Map()

    Connections {
        target: root.calculator
        enabled: root.isActive
        function onEntriesChanged(): void {
            root.rebuild();
        }
        function onHistoryChanged(): void {
            root.rebuild();
        }
        function onCardSelected(): void {
            root.selectedItem = null;
        }
    }

    function onActivated(initialQuery: string): void {
        handleInput(initialQuery ?? "");
    }

    function onDeactivated(): void {
        root.calculator?.clear();
    }

    function handleInput(q: string): void {
        root.query = q ?? "";
        root.calculator?.update(root.query, true);
        rebuild();
    }

    function rebuild(): void {
        if (!root.calculator)
            return;
        const q = root.query.trim().toLowerCase();
        const rows = root.calculator.entries.slice();
        for (const h of root.calculator.history) {
            if (q && !h.expr.toLowerCase().includes(q))
                continue;
            rows.push(root.cached(h));
        }
        model.values = rows;
    }

    function cached(h: var): var {
        const key = h.expr + "|" + h.at;
        let e = root.entryCache.get(key);
        if (!e) {
            const today = new Date().toDateString() === new Date(h.at).toDateString();
            e = {
                leftIcon: "\uebea", // tabler history
                header: h.text,
                text: h.expr,
                rightText: Qt.formatDateTime(new Date(h.at), today ? "HH:mm" : "dd.MM"),
                onClicked: () => root.calculator.copyText(h.copy, false),
                onAltClicked: () => {
                    root.requestSetInput(h.expr);
                    root.handleInput(h.expr);
                },
                onSelected: () => root.selectedItem = h
            };
            root.entryCache.set(key, e);
        }
        return e;
    }

    function handleKey(event: var): bool {
        if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ShiftModifier) && root.selectedItem) {
            root.calculator.forget(root.selectedItem.expr);
            root.selectedItem = null;
            return true;
        }
        return false;
    }
}
