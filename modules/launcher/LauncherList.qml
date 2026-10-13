import QtQuick
import Quickshell
import "../../components"
import "LauncherMetrics.js" as Metrics
import "../../config"

// Result list. Not a drag-Flickable (module content stays press-transparent
// for the swipe-up close): the selection is our own index (ListView's
// currentIndex would auto-scroll on its own), the wheel steps it, and the
// view scrolls on a spring just enough to keep the selection in view.
//
// Motion: plugins keep one row object per item, and the view gets a
// ScriptModel (identity diff) over a WINDOW of the results — the visible
// rows + a margin growing with the selection — whose rows all stay created
// (cacheBuffer). A big reorder (first letter, erasing a word: mostly row
// MOVES from/to far below) thus becomes inserts/removes at the window edge:
// rows that come fade in out of a blur, rows that go dissolve (row
// `appear`), rows that stay FLIP-slide to their new slots on springs, the
// selection plate slides between rows. Without the window a row moved in
// from off-screen was created fresh (no animation) and one moved away was
// destroyed at once. A different `listKey` (another plugin, the "!"
// picker) swaps the whole list: blur-fade out, swap, in.
Item {
    id: root
    required property var entries
    required property string listKey
    required property var theme
    required property var cfg
    // Index to land on after the next entries change (-1 = top); the
    // owner resets it via selectionApplied().
    property int pendingSelection: -1
    property string emptyText: I18n.tr("Nothing found")

    // What the view renders: lags `entries` while a list swap fades out.
    property var rows: []
    property string shownKey: ""
    property bool swapping: false

    property int selected: 0
    readonly property var current: root.rows[root.selected] ?? null

    // Rows handed to the view: the visible ones + windowExtra, and always
    // a few past the FURTHEST selection of this list (grow-only until the
    // rows change). Shrinking it while scrolling back up removed rows at
    // the bottom, the content got shorter and ListView clamped contentY by
    // itself — an unanimated jump.
    property int reach: 0
    // While scrolling, a whole list of rows stays created AHEAD of the
    // selection: rows lagging on their scroll springs pull the next ones
    // into view early, and those must already be there (no empty band at
    // the edge). Rows past `baseCount` come only from this growth: they
    // appear without the new-result fade (`quietAdd`).
    readonly property int baseCount: root.cfg.maxShown + root.cfg.windowExtra
    readonly property int windowCount: root.reach > 0
        ? Math.max(root.baseCount, root.reach + root.cfg.windowExtra + root.cfg.maxShown + 1) : root.baseCount
    ScriptModel {
        id: windowModel
        values: root.rows.slice(0, root.windowCount)
    }

    signal selectionApplied

    function move(step: int): void {
        if (root.rows.length === 0)
            return;
        root.selected = Math.max(0, Math.min(root.rows.length - 1, root.selected + step));
    }

    Component.onCompleted: root.finishSwap()

    onListKeyChanged: {
        // First list (the module is still being built): no swap to show.
        if (root.shownKey === "") {
            root.finishSwap();
        } else if (root.listKey === root.shownKey) {
            // Swapped back before the old list was gone: keep it.
            root.swapping = false;
            root.rows = root.entries;
        } else {
            root.swapping = true;
            // Already faded out (no p change would come): swap right away.
            if (swap.p < 0.02)
                root.finishSwap();
        }
    }
    onEntriesChanged: if (!root.swapping && root.listKey === root.shownKey) root.rows = root.entries

    function finishSwap(): void {
        root.rows = root.entries;
        root.shownKey = root.listKey;
        root.jumpScroll = true;
        root.scrollTo(0);
        root.jumpScroll = false;
        root.swapping = false;
    }

    // Entries changed (typing, plugin switch): back to the top unless the
    // plugin asked to keep a row. Rows slide under a resting cursor for a
    // moment — hover must not steal the selection meanwhile.
    // New results land in place: no scroll animation for this selection.
    property bool jumpScroll: false

    onRowsChanged: {
        const want = root.pendingSelection >= 0 ? root.pendingSelection : 0;
        root.reach = 0;
        root.jumpScroll = true;
        root.selected = -1;
        root.selected = Math.min(want, Math.max(0, root.rows.length - 1));
        root.jumpScroll = false;
        if (root.pendingSelection >= 0)
            root.selectionApplied();
        hoverHold.restart();
    }

    onSelectedChanged: {
        if (root.selected < 0)
            return;
        root.reach = Math.max(root.reach, root.selected);
        const e = root.rows[root.selected];
        if (typeof e?.onSelected === "function")
            e.onSelected();
        const top = Metrics.itemTop(root.cfg, root.rows, root.selected);
        const bottom = top + Metrics.itemHeight(root.cfg, e);
        if (top < view.contentY)
            root.scrollTo(top);
        else if (bottom > view.contentY + root.height)
            root.scrollTo(bottom - root.height);
        else if (root.selected === 0)
            root.scrollTo(0);
    }

    // Scrolling moves contentY AT ONCE; the motion is on the ROWS: each
    // row (and the selection plate) offsets itself back by the scroll step
    // and springs that offset to 0 (LauncherItem.kickScroll), rows farther
    // from the selection a bit softer (`scrollStagger`), so the list glides
    // like elements on springs. Only OUR scrolls kick: ListView shifts
    // contentY itself when rows are inserted above the top one, animating
    // that read as the whole list jumping up and back on the first letter.
    // (A Behavior on contentY was stopped by ListView's own writes.)
    signal scrolled(real delta)

    function scrollTo(y: real): void {
        const d = y - view.contentY;
        view.contentY = y;
        if (!root.jumpScroll && Math.abs(d) > 0.01)
            root.scrolled(d);
    }

    Timer {
        id: hoverHold
        interval: root.cfg.hoverHoldMs
    }

    FadeBlur {
        id: swap
        anchors.fill: parent
        shown: !root.swapping
        onPChanged: if (root.swapping && swap.p < 0.02) root.finishSwap()

        Item {
            anchors.fill: parent
            clip: true

            // Selection plate: springs to the TARGET slot of the selected
            // row (never to an animated y), shifted by the live scroll.
            // Stretches along its flight (VelocityDeform, like the OCR panel)
            // — measured on the slot in LIST coords, so a held key that
            // scrolls the list (plate still on screen) stretches it too.
            Rectangle {
                id: plate
                transform: VelocityDeform {
                    item: plate
                    useSource: true
                    sourceY: plate.slotY + plate.slotH / 2
                    // Attenuate by the ROW height (the motion axis), not the
                    // list width: 620 px wide cut the stretch to ~9 %.
                    sizeW: plate.slotH
                    sizeH: plate.slotH
                }
                property real slotY: Metrics.itemTop(root.cfg, root.rows, Math.max(0, root.selected))
                property real slotH: Metrics.itemHeight(root.cfg, root.current)
                Behavior on slotY { Spring { stiffness: root.cfg.motionStiffness; damp: root.cfg.motionDamping; eps: 0.25 } }
                Behavior on slotH { Spring { stiffness: root.cfg.motionStiffness; damp: root.cfg.motionDamping; eps: 0.25 } }
                y: plate.slotY - view.contentY + plate.scrollShift
                // Rides the scroll like the selected row (see scrollTo).
                property real scrollShift: 0
                Behavior on scrollShift {
                    id: plateScroll
                    Spring { id: plateScrollSpring; stiffness: root.cfg.scrollStiffness ?? 3; damp: root.cfg.scrollDamping ?? 0.5; eps: 0.25 }
                }
                Connections {
                    target: root
                    function onScrolled(d: real): void {
                        plateScroll.enabled = false;
                        plate.scrollShift += d;
                        plateScroll.enabled = true;
                        plate.scrollShift = 0;
                    }
                }
                width: parent.width
                height: plate.slotH
                radius: root.cfg.itemRadius
                color: root.theme.cardBg
                opacity: root.rows.length > 0 ? 1 : 0
                Behavior on opacity { Spring { eps: 0.01 } }
            }
        }

        ListView {
            id: view
            anchors.fill: parent
            clip: true
            interactive: false
            // Keep every row of the window created (see header).
            cacheBuffer: Metrics.maxListHeight(root.cfg) * 2
            // Rows lagging on their scroll springs show up to about a list
            // height away from their slots: rows in these margins are
            // created SYNCHRONOUSLY (cacheBuffer ones are incubated over
            // several frames) so the lag zone is never an empty band.
            displayMarginBeginning: Metrics.maxListHeight(root.cfg)
            displayMarginEnd: Metrics.maxListHeight(root.cfg)
            // No ListView current item: the selection is `root.selected`. The
            // default currentIndex 0 kept the first row as a special item
            // whose remove/move never finished (it stuck in slot 0 over the
            // newcomer); ListView re-arms it to 0 when rows arrive.
            currentIndex: -1
            highlightFollowsCurrentItem: false
            keyNavigationEnabled: false
            onCountChanged: if (view.currentIndex !== -1) view.currentIndex = -1
            spacing: root.cfg.itemSpacing
            model: windowModel
            readonly property bool gliding: plateScrollSpring.running || hoverHold.running

            // View transitions only flip row flags; the motion itself is the
            // row's own Behavior springs (LauncherItem). A SpringAnimation
            // INSIDE a view transition never picks up its target: moved rows
            // kept their old y, removed rows stayed fully visible. Moves have
            // no transition at all (the row FLIP-slides itself), so the view
            // places rows at their new slots at once.
            add: Transition {
                PropertyAction { property: "entering"; value: true }
            }
            remove: Transition {
                SequentialAnimation {
                    PropertyAction { property: "leaving"; value: true }
                    PauseAnimation { duration: root.cfg.removeMs }
                }
            }

            delegate: LauncherItem {
                id: row
                width: ListView.view.width
                theme: root.theme
                cfg: root.cfg
                current: index === root.selected
                quietAdd: index >= root.baseCount
                Connections {
                    target: root
                    function onScrolled(d: real): void {
                        row.kickScroll(d, Math.abs(row.index - root.selected));
                    }
                }
                onHovered: if (!view.gliding) root.selected = index
            }
        }

        Text {
            anchors.centerIn: parent
            text: root.emptyText
            color: root.theme.cardDim
            font.pixelSize: root.cfg.fontSize
            opacity: root.rows.length === 0 ? 1 : 0
            Behavior on opacity { Spring { eps: 0.01 } }
        }
    }

    WheelHandler {
        property real acc: 0
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            acc += event.angleDelta.y;
            while (Math.abs(acc) >= 120) {
                root.move(acc > 0 ? -1 : 1);
                acc -= acc > 0 ? 120 : -120;
            }
        }
    }
}
