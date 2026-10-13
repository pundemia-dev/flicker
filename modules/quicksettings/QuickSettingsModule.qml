import QtQuick
import "../../components"
import "QsCatalog.js" as QsCatalog
import "QsGrid.js" as QsGrid
import "QsMetrics.js" as QsMetrics
import "../../components/Knockout.js" as Knockout

// Quick Settings = iOS Control Center: tabs (pages) of a cols x N grid of
// square cells (Config.quicksettings), cards of several footprints
// (QsCatalog), each laying its content out by its own shape (QsCard.form).
// Layout state lives in services/ControlCenter (shared, persisted); the
// island size is derived from it (QsMetrics): the viewport fits the
// TALLEST page, pages slide vertically inside it (one strip, offset by
// the live `pagePos`), so a swipe never resizes the island.
//
// Tabs: rail on the right (QsTabRail, icon per page picked from its
// content). Switch by vertical swipe/drag anywhere on the grid (cards
// forward theirs), the wheel, or a rail tap. Close (user): tap an empty
// spot, or swipe up STARTING in the bottom `closeZone`. This module owns
// all its presses (background MouseArea below the cards), so GestureZones
// never sees them.
//
// Edit mode (long press on any card, iOS): drag a card to move it (others
// are pushed aside live, equal cards swap; over a rail icon it flips to
// that tab, over "+" it opens a new one), drag the bottom-right arc to
// resize (nearest allowed footprint), "−" hides, the footer adds hidden
// cards back; "Готово", a tap on empty space or closing saves. An extra
// empty row below the grid takes drops; empty tabs are dropped on save.
Item {
    id: root
    required property var services
    signal closeRequested
    signal openRequested(string name, var payload)

    readonly property var cc: root.services.controlCenter
    readonly property var cfg: root.services.config.quicksettings
    readonly property var theme: root.services.theme
    readonly property var frost: root.services.frost ?? null
    readonly property real unit: root.cfg.unit
    readonly property real pitch: root.cfg.unit + root.cfg.spacing
    readonly property bool editing: root.cc.editing

    readonly property real viewportH: QsMetrics.viewportHeight(root.cfg, root.cc.rows, root.editing)
    readonly property real bodyH: Math.max(root.viewportH, QsMetrics.railHeight(root.cfg, root.cc.railIcons))
    // Page stride in the strip: the next page starts a margin below the
    // viewport (outside it; the viewport clips while pages move).
    readonly property real stride: root.viewportH + root.cfg.margins

    // Live page position (fractional mid-swipe), springs to cc.page.
    property real pagePos: root.cc.page
    property bool paging: false
    readonly property bool moving: root.paging || Math.abs(root.pagePos - root.cc.page) > 0.002
    Behavior on pagePos {
        enabled: !root.paging
        Spring { eps: 0.001 }
    }
    Connections {
        target: root.cc
        function onPageChanged(): void {
            if (!root.paging)
                root.pagePos = root.cc.page;
        }
    }

    // Frost knockouts in module coords: every shown card (its pieces), live
    // through slides/morphs (the reads below are the binding's triggers),
    // cut to the viewport while pages slide. The lifted card is left out:
    // overlapping holes would cancel in the even-odd tint.
    readonly property var knockouts: {
        const out = [];
        const vp = root.moving ? { x0: viewport.x, y0: viewport.y, x1: viewport.x + viewport.width, y1: viewport.y + viewport.height } : null;
        void strip.y;
        for (let i = 0; i < cardRepeater.count; i++) {
            const c = cardRepeater.itemAt(i);
            if (!c || !c.visible || c.opacity < 0.5 || c.follow)
                continue;
            void c.x, c.y, c.width, c.height, c.scale;
            for (const k of c.knockouts) {
                const h = vp ? Knockout.clipped(Knockout.mapped(c, root, k), vp) : Knockout.mapped(c, root, k);
                if (h)
                    out.push(h);
            }
        }
        return out;
    }

    // Card being moved/resized (only one at a time).
    property string activeId: ""

    function cellPx(n: int): real {
        return n * root.pitch;
    }
    function spanPx(n: int): real {
        return n * root.unit + (n - 1) * root.cfg.spacing;
    }
    // Tab icon = glyph of the page's biggest card (first in reading order
    // on ties); an empty page gets a dot.
    function pageGlyph(page: var): string {
        let best = null;
        for (const i of page)
            if (!best || i.w * i.h > best.w * best.h)
                best = i;
        return best ? QsCatalog.glyphOf(best.id) : "";
    }

    // Vertical swipe (background or forwarded by a card) -------------------
    property string swipeMode: ""
    property bool swipeFired: false
    property real swipeDy: 0
    function swipeStart(y: real): void {
        root.swipeDy = 0;
        root.swipeFired = false;
        root.swipeMode = y >= root.height - root.cfg.closeZone ? "close" : "page";
        if (root.swipeMode === "page")
            root.paging = true;
    }
    function swipeUpdate(dy: real): void {
        root.swipeDy = dy;
        if (root.swipeMode === "close") {
            if (!root.swipeFired && dy < -root.cfg.closeDistance) {
                root.swipeFired = true;
                root.closeRequested();
            }
            return;
        }
        // Content follows the finger; rubber band past the first/last tab.
        let pos = root.cc.page - dy / root.stride;
        const last = root.cc.pages.length - 1;
        if (pos < 0)
            pos *= 0.3;
        else if (pos > last)
            pos = last + (pos - last) * 0.3;
        root.pagePos = pos;
    }
    function swipeEnd(): void {
        if (root.swipeMode === "page") {
            const d = root.cfg.pageSwipeDistance;
            const target = root.cc.page + (root.swipeDy < -d ? 1 : root.swipeDy > d ? -1 : 0);
            root.paging = false;
            root.cc.setPage(target);
            root.pagePos = root.cc.page;
        }
        root.swipeMode = "";
    }

    Component.onDestruction: root.cc.endEdit()

    QsCardFactory {
        id: factory
        services: root.services
        onOpenRequested: (name, payload) => root.openRequested(name, payload)
    }

    // Empty space: tap closes (edit mode: leaves edit), vertical swipe
    // pages/closes, wheel flips tabs.
    MouseArea {
        id: bg
        anchors.fill: parent
        property point start
        property bool swiping: false
        property real wheelAcc: 0
        onPressed: mouse => {
            start = Qt.point(mouse.x, mouse.y);
            swiping = false;
        }
        onPositionChanged: mouse => {
            const dy = mouse.y - start.y;
            if (!swiping && Math.abs(dy) > 8 && Math.abs(dy) > Math.abs(mouse.x - start.x)) {
                swiping = true;
                root.swipeStart(start.y);
            }
            if (swiping)
                root.swipeUpdate(dy);
        }
        onReleased: mouse => {
            if (swiping) {
                swiping = false;
                root.swipeEnd();
            } else if (Math.hypot(mouse.x - start.x, mouse.y - start.y) < 8) {
                if (root.editing)
                    root.cc.endEdit();
                else
                    root.closeRequested();
            }
        }
        onCanceled: {
            if (swiping) {
                swiping = false;
                root.swipeEnd();
            }
        }
        onWheel: wheel => {
            wheelAcc += wheel.angleDelta.y;
            if (Math.abs(wheelAcc) >= 120) {
                root.cc.setPage(root.cc.page + (wheelAcc < 0 ? 1 : -1));
                wheelAcc = 0;
            }
        }
    }

    Item {
        id: viewport
        x: root.cfg.margins
        y: root.cfg.margins + (root.bodyH - root.viewportH) / 2
        width: QsMetrics.innerWidth(root.cfg)
        height: root.viewportH
        // Clip only while pages slide: at rest the edit badges and the lift
        // scale may poke past the grid edge.
        clip: root.moving

        // Empty-slot dots in edit mode (iOS shows the grid it snaps to).
        Repeater {
            model: root.editing && !root.moving ? root.cfg.cols * QsMetrics.gridRows(root.cc.rows, true) : 0
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

        Item {
            id: strip
            width: parent.width
            height: parent.height
            y: -root.pagePos * root.stride

            Repeater {
                id: cardRepeater
                model: QsCatalog.IDS
                delegate: QsCard {
                    id: card
                    required property string modelData
                    readonly property var rect: root.cc.rectOf(modelData)
                    // Last placed rect, kept while the card hides (scale-out in place).
                    property var last: rect ?? ({ x: 0, y: 0, w: 1, h: 1, page: 0 })
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
                    frost: root.frost
                    editing: root.editing
                    pointerSpace: root
                    content: factory.componentFor(modelData)
                    spanW: last.w
                    spanH: last.h
                    z: follow ? 2 : (root.activeId === modelData ? 1 : 0)

                    // Page offset is instant (like the strip's own y): a
                    // stride change (tallest page resized) must not spring
                    // the card against the already-jumped strip. Only the
                    // in-page part springs (cell row/col).
                    readonly property real pageY: last.page * root.stride
                    property real cellY: follow ? grabOrigin.y + dragOffset.y - pageY : root.cellPx(last.y)
                    Behavior on cellY { enabled: card.animate; Spring {} }

                    x: follow ? grabOrigin.x + dragOffset.x : root.cellPx(last.x)
                    y: pageY + cellY
                    width: root.spanPx(last.w)
                    height: root.spanPx(last.h)
                    Behavior on x { enabled: card.animate; Spring {} }
                    Behavior on width { enabled: card.animate; Spring {} }
                    Behavior on height { enabled: card.animate; Spring {} }

                    scale: rect ? (follow ? 1.06 : 1) : 0.4
                    opacity: rect ? 1 : 0
                    // Other tabs exist only while pages slide (the edit
                    // footer sits where the next page waits).
                    visible: opacity > 0.01 && (follow || root.moving || last.page === root.cc.page)
                    Behavior on scale { Spring { eps: 0.005 } }
                    Behavior on opacity { Spring { eps: 0.01 } }

                    onHoldRequested: root.cc.beginEdit()
                    onRemoveRequested: root.cc.remove(modelData)
                    onSwipeStarted: y => root.swipeStart(y)
                    onSwipeUpdated: dy => root.swipeUpdate(dy)
                    onSwipeEnded: root.swipeEnd()

                    onMoveStarted: {
                        root.activeId = modelData;
                        grabOrigin = Qt.point(x, y);
                        dragOffset = Qt.point(0, 0);
                        animate = false;
                        follow = true;
                    }
                    onMoveUpdated: (dx, dy, px, py) => {
                        dragOffset = Qt.point(dx, dy);
                        const r = root.cc.itemOf(modelData);
                        if (!r)
                            return;
                        // Over the rail: flip to the hovered tab / open a new one.
                        if (px >= rail.x) {
                            const i = rail.indexAt(py - rail.y);
                            if (i === -2)
                                root.cc.addPage();
                            else if (i >= 0 && i !== root.cc.page)
                                root.cc.setPage(i);
                        }
                        // Target cell under the card's top-left on the current
                        // tab; one row past it = the edit drop row.
                        const page = root.cc.pages[root.cc.page] ?? [];
                        const maxRow = QsGrid.rowsOf(page.filter(i => i.id !== modelData));
                        const cx = Math.max(0, Math.min(root.cfg.cols - r.w, Math.round((grabOrigin.x + dx) / root.pitch)));
                        const cy = Math.max(0, Math.min(maxRow, Math.round((grabOrigin.y + dy - root.cc.page * root.stride) / root.pitch)));
                        root.cc.previewMove(modelData, root.cc.page, cx, cy);
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
    }

    QsTabRail {
        id: rail
        x: viewport.x + viewport.width + root.cfg.spacing
        y: root.cfg.margins
        width: root.cfg.railWidth
        height: root.bodyH
        cfg: root.cfg
        theme: root.theme
        frost: root.frost
        glyphs: root.cc.shown.map(p => root.pageGlyph(p))
        pagePos: root.pagePos
        editing: root.editing
        opacity: root.cc.railShown ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { Spring { eps: 0.01 } }
        onPageRequested: i => root.cc.setPage(i)
        onAddRequested: root.cc.addPage()
    }

    // Session menu: top-right corner, in the rail column (not a card).
    QsSessionButton {
        x: rail.x + rail.width - width
        y: QsMetrics.sessionTop(root.cfg)
        cfg: root.cfg
        theme: root.theme
        frost: root.frost
        visible: root.cfg.sessionButton ?? false
        onClicked: root.openRequested("session", {})
    }

    QsEditFooter {
        x: root.cfg.margins
        y: root.cfg.margins + root.bodyH + root.cfg.spacing
        width: viewport.width
        height: QsMetrics.footerHeight(root.cfg, root.cc.hiddenIds.length)
        cfg: root.cfg
        theme: root.theme
        frost: root.frost
        hiddenIds: root.cc.hiddenIds
        opacity: root.editing ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { Spring { eps: 0.01 } }
        onAddRequested: id => root.cc.add(id)
        onDoneRequested: root.cc.endEdit()
    }
}
