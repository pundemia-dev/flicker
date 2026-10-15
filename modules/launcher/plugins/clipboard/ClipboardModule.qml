import QtQuick
import Quickshell
import "../../api"
import "../../../../config"

// Clipboard history (pShell clipboard plugin port): cliphist entries as
// rows by type (image row / colour swatch / url / path / text), preview in
// the side panel. Enter copies (+ auto-paste when cfg.clipboard.autoPaste),
// Alt+Enter copies only.
LauncherPlugin {
    id: root

    property string query: ""
    property var selectedRecord: null

    ClipboardService {
        id: service
        cfg: root.cfg?.clipboard ?? null
        onRecordsChanged: root.rebuild()
    }

    // Our own cliphist watcher reports every store (images too).
    Connections {
        target: root.host?.clipboardWatch ?? null
        ignoreUnknownSignals: true
        function onRevisionChanged(): void {
            service.changed();
        }
    }

    ScriptModel {
        id: model
    }
    listModel: model

    function onActivated(initialQuery: string): void {
        // Re-list on every activation: image copies made while closed fire
        // no clipboardTextChanged.
        service.refresh();
        handleInput(initialQuery ?? "");
    }

    function onDeactivated(): void {
        root.selectedRecord = null;
    }

    function handleInput(q: string): void {
        root.query = (q ?? "").trim().toLowerCase();
        rebuild();
    }

    // Rows cached by cliphist id: ScriptModel diffs by identity, so a stable
    // object per entry lets only the rows that come or go animate.
    property var entryCache: new Map()

    function rebuild(): void {
        const q = root.query;
        const found = service.records.filter(r => !q || (r.value ?? r.firstLine ?? r.raw ?? "").toLowerCase().includes(q));
        const live = new Map();
        model.values = found.map(r => {
            const e = root.entryCache.get(r.id) ?? root.toEntry(r);
            live.set(r.id, e);
            return e;
        });
        for (const r of service.records)
            if (!live.has(r.id) && root.entryCache.has(r.id))
                live.set(r.id, root.entryCache.get(r.id));
        root.entryCache = live;
        root.selectedRecord = found[0] ?? null;
        root.hasRightPanel = found.length > 0;
    }

    function toEntry(rec: var): var {
        const base = {
            onClicked: () => {
                service.copy(rec, service.autoPaste);
                root.requestClose(true);
            },
            onAltClicked: () => {
                service.copy(rec, false);
                root.requestClose(true);
            },
            onSelected: () => root.selectedRecord = rec
        };
        switch (rec.type) {
        case "image":
            return Object.assign(base, {
                header: I18n.tr("Image"),
                text: (rec.width && rec.height ? rec.width + "×" + rec.height : "") + (rec.size ? " · " + rec.size : ""),
                backgroundImage: "file://" + rec.imagePath
            });
        case "color":
            return Object.assign(base, { header: rec.value, swatchColor: rec.hex, rightText: rec.label });
        case "url":
            return Object.assign(base, { leftIcon: "", header: rec.host, text: rec.value }); // tabler link
        case "path":
            return Object.assign(base, { leftIcon: "", header: rec.base, text: rec.dir }); // tabler file
        default:
            return Object.assign(base, {
                leftIcon: "", // tabler typography
                header: rec.firstLine,
                text: rec.lineCount > 1 ? I18n.tr("%1 chars · %2 lines").arg(rec.chars).arg(rec.lineCount) : I18n.tr("%1 chars").arg(rec.chars)
            });
        }
    }

    rightPanelComponent: Component {
        ClipboardPreview {
            rec: root.selectedRecord
            svc: service
            theme: root.theme
            cfg: root.cfg
        }
    }
}
