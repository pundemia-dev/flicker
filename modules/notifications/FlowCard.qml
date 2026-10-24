import QtQuick
import "../../components"
import "../../config"

// Flow mode of the notifications module: the incoming card plus its
// gestures (iOS):
//  - tap = open the app (default action + focus its window / start it)
//  - drag down = the island follows the finger (dashboard drawer feel) and
//    snaps open past `flowPullThreshold`: context buttons slide in below
//    (sender actions, Reply, Dismiss); drag up collapses them again
//  - long press = reply in place (inline reply: the app is never focused);
//    without inline reply it opens the context buttons instead
//  - swipe up on the collapsed card = close (the card grabs presses, so it
//    forwards the module close itself — GestureZones never sees them)
// The island height = `preferredHeight` (base flow height + the panel).
Item {
    id: root

    property var entry
    property var service
    property var cfg
    property var theme
    // Island height of the plain card (config modules["notifications:flow"]).
    property real baseHeight: 90
    signal closeRequested

    readonly property real margin: 14
    readonly property real inset: root.cfg?.flowActionInset ?? 28
    readonly property real threshold: root.cfg?.flowPullThreshold ?? 36
    readonly property real closeDistance: 30

    // "" collapsed | "actions" | "mute" | "reply"
    property string stage: ""
    property bool dragging: false
    property real pull: 0

    readonly property real preferredHeight: root.baseHeight + panel.extraFor(root.dragging, root.pull)
    // Island: keyboard for the reply field, no auto-close while in use.
    readonly property bool wantsKeyboard: root.stage === "reply"
    readonly property bool holdOpen: root.stage !== "" || ma.pressed

    // Shared-element slot "time" (the bar clock docks in the card).
    readonly property Item timeSlot: card.timeSlot

    NotificationCard {
        id: card
        x: root.margin
        y: root.margin
        width: root.width - 2 * root.margin
        height: root.baseHeight - 2 * root.margin
        notif: root.entry
        cfg: root.cfg
        // Hidden text shows once the card is pulled open.
        redacted: (root.service?.redact ?? false) && root.stage === ""
    }

    // Gestures (below the panel: its buttons take their own presses).
    MouseArea {
        id: ma
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        pressAndHoldInterval: root.cfg?.flowLongPressMs ?? 450

        property real pressY: 0
        property real pressX: 0
        property string axis: ""
        property bool held: false
        property bool fired: false

        onPressed: mouse => {
            pressX = mouse.x;
            pressY = mouse.y;
            axis = "";
            held = false;
            fired = false;
        }
        onPositionChanged: mouse => {
            const dx = mouse.x - pressX;
            const dy = mouse.y - pressY;
            if (axis === "" && !held && Math.hypot(dx, dy) > 8)
                axis = Math.abs(dy) >= Math.abs(dx) ? "y" : "x";
            if (axis !== "y")
                return;
            if (root.stage === "" && dy < -root.closeDistance) {
                if (!fired) {
                    fired = true;
                    root.closeRequested();
                }
                return;
            }
            root.dragging = true;
            root.pull = dy;
        }
        onPressAndHold: {
            if (axis !== "")
                return;
            held = true;
            root.stage = root.entry?.canReply ? "reply" : "actions";
        }
        onReleased: {
            if (root.dragging) {
                if (root.stage === "" && root.pull > root.threshold)
                    root.stage = "actions";
                else if (root.stage !== "" && root.pull < -root.threshold)
                    root.stage = "";
            } else if (axis === "" && !held) {
                root.service?.open(root.entry);
                root.closeRequested();
            }
            root.dragging = false;
            root.pull = 0;
        }
        onCanceled: {
            root.dragging = false;
            root.pull = 0;
        }
    }

    // ── Panel under the card: context buttons / reply field ──
    NotificationActions {
        id: panel
        x: root.inset
        y: root.baseHeight - root.margin + panel.spacing
        width: root.width - 2 * root.inset
        entry: root.entry
        cfg: root.cfg
        theme: root.theme
        stage: root.stage
        // Follows the island's LIVE height (its spring).
        reveal: Math.max(0, Math.min(1, (root.height - root.baseHeight) / panel.panelExtra))
        onStageRequested: s => root.stage = s
        onFinished: root.closeRequested()
    }
}
