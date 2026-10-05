import QtQuick
import "../../../components/Knockout.js" as Knockout
import "../../../components"
import "../games"

// Notification Center (history view of the notifications module), iOS
// style: entries grouped by app (newest group first, stacks fan out on
// tap), swipe a tile left to dismiss, wheel to scroll. With no history it
// shows the mini-game deck instead (swipe left/right to switch games).
//
// `preferredHeight` is the target island height (Island clamps it to
// modules["notifications:center"].height): the list fits its content, the
// game deck uses notifications.gameHeight.
Item {
    id: root

    property var service
    property var cfg
    property var theme
    property var frost: null
    signal closeRequested

    readonly property var history: root.service?.history ?? []
    readonly property bool empty: root.history.length === 0
    readonly property real margin: 12
    readonly property real headerH: 34
    readonly property real gap: root.cfg?.centerSpacing ?? 8
    // Viewport gap under the header; list inset inside the viewport (room
    // for the hover ✕ that sticks out of a tile's top-left corner).
    readonly property real viewportTop: 4
    readonly property real listInset: 6

    // Frost knockouts in center coords: every group's tiles, scrolled and
    // cut to the clipped list viewport. None for the game deck.
    readonly property var knockouts: {
        if (root.empty || listBox.opacity < 0.5)
            return [];
        void list.y, viewport.y, viewport.height, viewport.width;
        const p0 = viewport.mapToItem(root, 0, 0);
        const vp = { x0: p0.x, y0: p0.y, x1: p0.x + viewport.width, y1: p0.y + viewport.height };
        const out = [];
        for (let i = 0; i < groupRepeater.count; i++) {
            const g = groupRepeater.itemAt(i);
            if (!g)
                continue;
            void g.y;
            for (const k of g.knockouts) {
                const h = Knockout.clipped(Knockout.mapped(g, root, k), vp);
                if (h)
                    out.push(h);
            }
        }
        return out;
    }

    // Expanded groups by app name (survives the Repeater rebuild that every
    // history change causes).
    property var expandedApps: ({})

    // Groups by app, in history order (history is newest first, so the
    // first entry seen makes a group's position = its newest arrival).
    readonly property var groups: {
        const order = [];
        const byApp = {};
        for (const e of root.history) {
            const app = (e?.appName ?? "").trim() || "Без имени";
            if (!byApp[app]) {
                byApp[app] = [];
                order.push(app);
            }
            byApp[app].push(e);
        }
        return order.map(app => ({ app: app, entries: byApp[app] }));
    }

    readonly property real contentHeight: {
        let h = 0;
        for (let i = 0; i < groupRepeater.count; i++)
            h += groupRepeater.itemAt(i)?.targetHeight ?? 0;
        return h + Math.max(0, groupRepeater.count - 1) * root.gap;
    }
    readonly property real preferredHeight: root.empty
        ? (root.cfg?.gameHeight ?? 210)
        : root.margin + root.headerH + root.viewportTop + 2 * root.listInset + root.contentHeight + root.margin

    function setExpanded(app: string, on: bool): void {
        const next = Object.assign({}, root.expandedApps);
        if (on)
            next[app] = true;
        else
            delete next[app];
        root.expandedApps = next;
    }

    // iOS tap: open the app (default action) and drop the notification.
    function activate(entry: var): void {
        if (!entry?.invokeDefault())
            return;
        if (root.history.includes(entry))
            entry.dismiss();
        root.closeRequested();
    }

    // ── List ──
    Item {
        id: listBox
        anchors.fill: parent
        anchors.margins: root.margin
        opacity: root.empty ? 0 : 1
        visible: opacity > 0.01
        Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }

        Item {
            id: header
            width: parent.width
            height: root.headerH

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: "Уведомления"
                font.pixelSize: 20
                font.weight: Font.Bold
                color: "#F0F4FB"
            }
            Pill {
                frost: root.frost
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                label: "Очистить всё"
                onClicked: root.service?.dismissAll(root.history)
            }
        }

        // Scroll viewport: no Flickable (it would grab presses and break
        // the swipe-up close) — wheel only, tiles keep their own swipes.
        Item {
            id: viewport
            anchors.top: header.bottom
            anchors.topMargin: root.viewportTop
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            // Room for the hover ✕ that sticks out above the first tile.
            anchors.leftMargin: -root.listInset
            anchors.rightMargin: -root.listInset
            clip: true

            readonly property real maxScroll: Math.max(0, list.height - viewport.height + 2 * root.listInset)
            property real scroll: 0
            onMaxScrollChanged: viewport.scroll = Math.min(viewport.scroll, viewport.maxScroll)

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 2;
                    viewport.scroll = Math.max(0, Math.min(viewport.maxScroll, viewport.scroll - delta));
                }
            }

            Column {
                id: list
                x: root.listInset
                y: root.listInset - scrollY
                width: viewport.width - 2 * root.listInset
                spacing: root.gap

                property real scrollY: viewport.scroll
                Behavior on scrollY { Spring { stiffness: 6; damp: 0.6 } }

                Repeater {
                    id: groupRepeater
                    model: root.groups

                    NotificationGroup {
                        required property var modelData
                        width: list.width
                        app: modelData.app
                        entries: modelData.entries
                        expanded: root.expandedApps[modelData.app] === true
                        cfg: root.cfg
                        theme: root.theme
                        frost: root.frost
                        onExpandRequested: on => root.setExpanded(modelData.app, on)
                        onActivated: entry => root.activate(entry)
                        onDismissGroup: root.service?.dismissAll(modelData.entries)
                        onCloseRequested: root.closeRequested()
                    }
                }
            }
        }
    }

    // ── Empty: mini-games ──
    Loader {
        anchors.fill: parent
        active: root.empty
        opacity: root.empty ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }

        sourceComponent: GameDeck {
            service: root.service
            cfg: root.cfg
            theme: root.theme
            onCloseRequested: root.closeRequested()
        }
    }
}
