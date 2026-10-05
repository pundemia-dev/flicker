import QtQuick
import "../../components"
import "QsCatalog.js" as QsCatalog
import "QsGrid.js" as QsGrid
import "QsMetrics.js" as QsMetrics

// Quick Settings = iOS Control Center: a cols x N grid of square cells
// (Config.quicksettings), cards of several footprints (QsCatalog), each
// laying its content out by its own shape (QsCard.form). Layout state
// lives in services/ControlCenter (shared, persisted); the island size is
// derived from it (QsMetrics), so the island follows every edit.
//
// Edit mode (long press on any card, iOS): drag a card to move it (others
// are pushed aside live, equal cards swap), drag the bottom-right arc to
// resize it (snaps to the nearest allowed footprint), "−" hides it, the
// footer adds hidden cards back; "Готово" (or closing the module) saves.
// An extra empty row below the grid takes drops.
//
// Cards grab presses (they forward swipe-up close themselves); gaps
// between them stay press-transparent for GestureZones below.
Item {
    id: root
    required property var services
    signal closeRequested
    signal openRequested(string name, var payload)

    readonly property var cc: root.services.controlCenter
    readonly property var cfg: root.services.config.quicksettings
    readonly property var theme: root.services.theme
    readonly property real unit: root.cfg.unit
    readonly property real pitch: root.cfg.unit + root.cfg.spacing
    readonly property bool editing: root.cc.editing

    // Card being moved/resized (only one at a time).
    property string activeId: ""

    function cellPx(n: int): real {
        return n * root.pitch;
    }
    function spanPx(n: int): real {
        return n * root.unit + (n - 1) * root.cfg.spacing;
    }

    Component.onDestruction: root.cc.endEdit()

    QsCardFactory {
        id: factory
        services: root.services
        onOpenRequested: (name, payload) => root.openRequested(name, payload)
    }

    Item {
        id: grid
        x: root.cfg.margins
        y: root.cfg.margins
        width: QsMetrics.innerWidth(root.cfg)
        height: root.spanPx(QsMetrics.gridRows(root.cc.rows, root.editing))

        // Empty-slot dots in edit mode (iOS shows the grid it snaps to).
        Repeater {
            model: root.editing ? root.cfg.cols * QsMetrics.gridRows(root.cc.rows, true) : 0
            delegate: Rectangle {
                required property int index
                x: root.cellPx(index % root.cfg.cols) + (root.unit - width) / 2
                y: root.cellPx(Math.floor(index / root.cfg.cols)) + (root.unit - height) / 2
                width: root.unit * 0.86
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: "#1FFFFFFF"
            }
        }

        Repeater {
            model: QsCatalog.IDS
            delegate: QsCard {
                id: card
                required property string modelData
                readonly property var rect: root.cc.rectOf(modelData)
                // Last placed rect, kept while the card hides (scale-out in place).
                property var last: rect ?? ({ x: 0, y: 0, w: 1, h: 1 })
                onRectChanged: if (rect) last = rect

                // Pointer-follow while moving; animate = springs on. Toggled
                // in this order on release so the return glides (see moveEnded).
                property bool follow: false
                property bool animate: true
                property point grabOrigin
                property point dragOffset

                cardId: modelData
                cfg: root.cfg
                theme: root.theme
                editing: root.editing
                content: factory.componentFor(modelData)
                spanW: last.w
                spanH: last.h
                z: follow ? 2 : (root.activeId === modelData ? 1 : 0)

                x: follow ? grabOrigin.x + dragOffset.x : root.cellPx(last.x)
                y: follow ? grabOrigin.y + dragOffset.y : root.cellPx(last.y)
                width: root.spanPx(last.w)
                height: root.spanPx(last.h)
                Behavior on x { enabled: card.animate; Spring {} }
                Behavior on y { enabled: card.animate; Spring {} }
                Behavior on width { enabled: card.animate; Spring {} }
                Behavior on height { enabled: card.animate; Spring {} }

                scale: rect ? (follow ? 1.06 : 1) : 0.4
                opacity: rect ? 1 : 0
                visible: opacity > 0.01
                Behavior on scale { Spring { eps: 0.005 } }
                Behavior on opacity { Spring { eps: 0.01 } }

                onHoldRequested: root.cc.beginEdit()
                onCloseRequested: root.closeRequested()
                onRemoveRequested: root.cc.remove(modelData)

                onMoveStarted: {
                    root.activeId = modelData;
                    grabOrigin = Qt.point(x, y);
                    dragOffset = Qt.point(0, 0);
                    animate = false;
                    follow = true;
                }
                onMoveUpdated: (dx, dy) => {
                    dragOffset = Qt.point(dx, dy);
                    const r = root.cc.items.find(i => i.id === modelData);
                    if (!r)
                        return;
                    // Target cell under the card's top-left; one row past
                    // the committed grid = the edit drop row.
                    const cx = Math.max(0, Math.min(root.cfg.cols - r.w, Math.round((grabOrigin.x + dx) / root.pitch)));
                    const cy = Math.max(0, Math.min(QsGrid.rowsOf(root.cc.items), Math.round((grabOrigin.y + dy) / root.pitch)));
                    root.cc.previewMove(modelData, cx, cy);
                }
                onMoveEnded: {
                    root.cc.commit();
                    animate = true;
                    follow = false;
                    root.activeId = "";
                }

                onResizeStarted: {
                    root.activeId = modelData;
                    grabOrigin = Qt.point(width, height);
                }
                onResizeUpdated: (dx, dy) => {
                    const r = root.cc.items.find(i => i.id === modelData);
                    if (!r)
                        return;
                    const wantW = (grabOrigin.x + dx + root.cfg.spacing) / root.pitch;
                    const wantH = (grabOrigin.y + dy + root.cfg.spacing) / root.pitch;
                    const s = QsGrid.nearestSize(QsCatalog.sizesOf(modelData).filter(s => s[0] <= root.cfg.cols), wantW, wantH);
                    root.cc.previewResize(modelData, s[0], s[1]);
                }
                onResizeEnded: {
                    root.cc.commit();
                    root.activeId = "";
                }
            }
        }
    }

    QsEditFooter {
        x: root.cfg.margins
        y: grid.y + grid.height + root.cfg.spacing
        width: grid.width
        height: QsMetrics.footerHeight(root.cfg, root.cc.hiddenIds.length)
        cfg: root.cfg
        theme: root.theme
        hiddenIds: root.cc.hiddenIds
        opacity: root.editing ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { Spring { eps: 0.01 } }
        onAddRequested: id => root.cc.add(id)
        onDoneRequested: root.cc.endEdit()
    }
}
