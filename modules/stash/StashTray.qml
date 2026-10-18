import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../components"
import "../../config"
import "StashTypes.js" as Types

// Tray view of the stash module: file grid (cfg.columns wide, island grows
// up to cfg.rowsMax rows, wheel-scrolls past that — no Flickable, it would
// grab presses and break the swipe-up close) + action row (refresh, open
// folder, send all, LocalSend receive toggle | clear all). While files are
// selected the row turns into the group bar (send · compress · delete |
// "n selected" | select all · clear). A drag on EMPTY grid space draws a
// rubber band (Ctrl adds to the selection), a click there clears it — so
// over a non-empty grid the swipe-up close starts outside the tiles.
// Keys (handleKey): Space = Quick Look of the hovered (else first
// selected / first) file, Ctrl+A, Delete = delete the selection, Esc =
// clear the selection.
Item {
    id: root
    required property var stash
    required property var localSend
    required property var cfg
    required property var theme
    required property real tileRadius
    signal sendRequested(var files)
    signal transcribeRequested(string file)
    signal previewRequested(string file)

    readonly property real actionsH: root.cfg.actionsHeight
    // The tile under the pointer (Space previews it).
    property string hoverPath: ""
    readonly property bool selecting: root.stash.selectedCount > 0

    function handleKey(event: var): bool {
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        if (event.key === Qt.Key_Space) {
            const sel = root.stash.selectedPaths();
            const target = root.hoverPath !== "" ? root.hoverPath : sel.length > 0 ? sel[0] : (root.stash.allPaths()[0] ?? "");
            if (target !== "")
                root.previewRequested(target);
            return true;
        }
        if (ctrl && event.key === Qt.Key_A) {
            root.stash.selectAll();
            return true;
        }
        if (event.key === Qt.Key_Delete && root.selecting) {
            root.deleteSelected();
            return true;
        }
        if (event.key === Qt.Key_Escape && root.selecting) {
            root.stash.clearSelection();
            return true;
        }
        return false;
    }

    function deleteSelected(): void {
        root.stash.removeMany(root.stash.selectedPaths());
        root.stash.clearSelection();
    }

    Item {
        id: viewport
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: actionRow.top
        anchors.bottomMargin: root.cfg.gap
        clip: true

        readonly property real maxScroll: Math.max(0, grid.height - viewport.height)
        property real scroll: 0
        onMaxScrollChanged: viewport.scroll = Math.min(viewport.scroll, viewport.maxScroll)

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 2;
                viewport.scroll = Math.max(0, Math.min(viewport.maxScroll, viewport.scroll - delta));
            }
        }

        // Rubber band on empty grid space (below the tiles: their presses
        // win). Box in GRID coords, so a scrolled grid selects the right rows.
        MouseArea {
            id: band
            anchors.fill: parent
            enabled: root.stash.count > 0
            property real x0: 0
            property real y0: 0
            property bool active: false
            property var base: ({})
            property rect box: Qt.rect(0, 0, 0, 0)

            onPressed: mouse => {
                band.x0 = mouse.x;
                band.y0 = mouse.y - grid.y;
                band.active = false;
                band.base = (mouse.modifiers & Qt.ControlModifier) ? Object.assign({}, root.stash.selection) : {};
            }
            onPositionChanged: mouse => {
                if (!band.pressed)
                    return;
                const gy = mouse.y - grid.y;
                if (!band.active && Math.hypot(mouse.x - band.x0, gy - band.y0) < root.cfg.rubberBandMin)
                    return;
                band.active = true;
                band.box = Qt.rect(Math.min(band.x0, mouse.x), Math.min(band.y0, gy), Math.abs(mouse.x - band.x0), Math.abs(gy - band.y0));
                const m = Object.assign({}, band.base);
                const step = root.cfg.cellSize + root.cfg.gap;
                for (let i = 0; i < root.stash.count; i++) {
                    const tx = (i % root.cfg.columns) * step, ty = Math.floor(i / root.cfg.columns) * step;
                    if (tx < band.box.x + band.box.width && tx + root.cfg.cellSize > band.box.x
                        && ty < band.box.y + band.box.height && ty + root.cfg.cellSize > band.box.y)
                        m[root.stash.model.get(i).filePath] = true;
                }
                root.stash.setSelection(Object.keys(m));
            }
            onReleased: {
                if (!band.active)
                    root.stash.clearSelection();
                band.active = false;
            }
        }

        Grid {
            id: grid
            y: -scrollY
            columns: root.cfg.columns
            spacing: root.cfg.gap

            property real scrollY: viewport.scroll
            Behavior on scrollY { Spring { stiffness: 6; damp: 0.6 } }

            Repeater {
                id: tiles
                model: root.stash.model

                StashTile {
                    id: tile
                    width: root.cfg.cellSize
                    height: root.cfg.cellSize
                    stash: root.stash
                    localSend: root.localSend
                    cfg: root.cfg
                    theme: root.theme
                    radius: root.tileRadius
                    onSendRequested: files => root.sendRequested(files)
                    onTranscribeRequested: file => root.transcribeRequested(file)
                    onPreviewRequested: file => root.previewRequested(file)
                    onHoveredChanged: {
                        if (tile.hovered)
                            root.hoverPath = tile.filePath;
                        else if (root.hoverPath === tile.filePath)
                            root.hoverPath = "";
                    }
                    menu: tileMenu
                    onMenuRequested: button => tileMenu.toggle(button, {
                        panel: tileMenuComp,
                        width: root.menuWidth(tile),
                        height: root.menuHeight(tile),
                        radius: root.tileRadius,
                        color: tile.menuButtonColor,
                        payload: tile
                    })
                }
            }
        }

        Rectangle {
            visible: band.active
            x: band.box.x
            y: band.box.y + grid.y
            width: band.box.width
            height: band.box.height
            radius: 4
            color: Qt.alpha(root.theme.cardBlue, 0.18)
            border.width: 1
            border.color: Qt.alpha(root.theme.cardBlue, 0.8)
        }

        // Empty state: icon + captions as one block, lifted above the island's
        // vertical middle (root sits inside symmetric padding; StashMetrics
        // emptyHeight leaves room for the action row below it).
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.height / 2 - height / 2 - 20
            spacing: 6
            visible: root.stash.count === 0

            IconImage {
                id: emptyIcon
                anchors.horizontalCenter: parent.horizontalCenter
                implicitSize: 56
                source: Quickshell.iconPath("folder-open", "folder")
                asynchronous: true
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("Tray is empty")
                color: root.theme.islandFg
                font.pixelSize: root.theme.fontSizeClock + 4
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("Drop a file onto the island")
                color: root.theme.subtleFg
                font.pixelSize: root.theme.fontSizeBody + 2
            }
        }
    }

    Item {
        id: actionRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.actionsH

        // ── Normal row ──
        Item {
            anchors.fill: parent
            opacity: root.selecting ? 0 : 1
            enabled: !root.selecting
            visible: opacity > 0.01
            Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }

            Row {
                spacing: root.cfg.gap
                height: parent.height

                RowButton {
                    glyph: ""
                    onClicked: root.stash.refresh()
                }
                RowButton {
                    glyph: ""
                    onClicked: root.stash.openFolder()
                }
                RowButton {
                    visible: root.localSend.enabled
                    disabled: root.stash.count === 0
                    glyph: ""
                    onClicked: root.sendRequested(root.stash.allPaths())
                }
                // LocalSend receive server on/off (session toggle).
                RowButton {
                    visible: root.localSend.enabled
                    checked: root.localSend.receiving
                    glyph: ""
                    onClicked: root.localSend.receiving = !root.localSend.receiving
                }
            }
            Text {
                anchors.centerIn: parent
                visible: root.stash.count > 0
                text: I18n.trN(root.stash.count, "%1 file", "%1 files")
                color: root.theme.subtleFg
                font.pixelSize: root.theme.fontSizeBody
            }
            RowButton {
                anchors.right: parent.right
                disabled: root.stash.count === 0
                glyph: ""
                onClicked: root.stash.clearAll()
            }
        }

        // ── Group actions over the selection ──
        Item {
            anchors.fill: parent
            opacity: root.selecting ? 1 : 0
            enabled: root.selecting
            visible: opacity > 0.01
            Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }

            Row {
                spacing: root.cfg.gap
                height: parent.height
                RowButton {
                    visible: root.localSend.enabled
                    checked: true
                    glyph: ""
                    onClicked: root.sendRequested(root.stash.selectedPaths())
                }
                RowButton {
                    glyph: ""
                    onClicked: {
                        root.stash.pack(root.stash.selectedPaths());
                        root.stash.clearSelection();
                    }
                }
                RowButton {
                    glyph: ""
                    onClicked: root.deleteSelected()
                }
            }
            Text {
                anchors.centerIn: parent
                text: I18n.trN(root.stash.selectedCount, "%1 selected", "%1 selected")
                color: root.theme.islandFg
                font.pixelSize: root.theme.fontSizeBody
            }
            Row {
                anchors.right: parent.right
                spacing: root.cfg.gap
                height: parent.height
                RowButton {
                    disabled: root.stash.selectedCount === root.stash.count
                    glyph: "立"
                    onClicked: root.stash.selectAll()
                }
                RowButton {
                    glyph: ""
                    onClicked: root.stash.clearSelection()
                }
            }
        }
    }

    component RowButton: IconButton {
        theme: root.theme
        width: root.actionsH
        height: root.actionsH
    }

    // Debug IPC (island stashMenu <i>, -1 folds it back).
    function debugMenu(i: int): void {
        const t = i >= 0 ? tiles.itemAt(i) : null;
        if (t)
            t.menuRequested(t.menuButton);
        else
            tileMenu.close();
    }

    // Tile menu: the tile's button grows into StashTileMenu over the tray.
    readonly property var mc: root.cfg.menu ?? ({})
    // As many buttons per row as fit the tray width (StashTileMenu derives
    // the same column count from the width it gets).
    function menuGrid(tile: var): var {
        const pad = root.mc.padding ?? 12, cell = root.mc.cellWidth ?? 54, sp = root.mc.spacing ?? 4;
        const n = Types.actions(tile, k => k).length;
        const fit = Math.max(1, Math.floor((root.width - 2 * pad + sp) / (cell + sp)));
        const rows = Math.ceil(n / fit);
        return { cols: Math.ceil(n / rows), rows };
    }
    function menuWidth(tile: var): real {
        const g = root.menuGrid(tile);
        return 2 * (root.mc.padding ?? 12) + g.cols * (root.mc.cellWidth ?? 54) + (g.cols - 1) * (root.mc.spacing ?? 4);
    }
    function menuHeight(tile: var): real {
        const pad = root.mc.padding ?? 12;
        const row = (root.mc.buttonSize ?? 40) + 4 + (root.mc.labelSize ?? 10) + 4;
        const rows = root.menuGrid(tile).rows;
        return 2 * pad + (root.mc.nameSize ?? 12) + 8 + rows * row + (rows - 1) * 2 * (root.mc.spacing ?? 4);
    }
    Component {
        id: tileMenuComp
        StashTileMenu {}
    }
    DropExpand {
        id: tileMenu
        anchors.fill: parent
        panelColor: root.theme.cardBg
    }
}
