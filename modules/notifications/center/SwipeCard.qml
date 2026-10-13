import QtQuick
import "../../../components"
import ".."

// One iOS-style notification tile of the Notification Center: the shared
// NotificationCard on a rounded plate. Swipe left past centerSwipeDistance
// dismisses (the tile flies out, then `dismissRequested`), a tap emits
// `tapped`, hovering shows the × button. With `actionable` (not a collapsed
// stack) a drag down / long press opens the context panel under the card
// like the flow card (NotificationActions); the tile then grows by
// `extraHeight` (the group lays tiles out by it) — `stage` is owned by
// the center (one open tile at a time), asked for via `stageRequested`.
//
// The tile accepts presses (it must, for swipes), so it also forwards the
// module's swipe-up close itself — GestureZones below never sees presses
// that start on a tile (AGENTS: module content must stay closable).
Item {
    id: root

    property var entry
    property var cfg
    property var theme
    // Island frost state: tile/plate surfaces fade with the frosted body.
    property var frost: null
    // Local px from the top hidden behind the card above (stack plates).
    property real coverTop: 0
    // Frost knockout (card coords): the visible surface; null while the
    // tile is mostly faded (thrown out / hidden plate).
    readonly property var knockout: {
        if (root.opacity * tile.opacity < 0.5 || root.height - root.coverTop < 0.5)
            return null;
        const r = 20, top = Math.max(0, r - root.coverTop);
        return { x: root.dragX, y: root.coverTop, w: root.width, h: root.height - root.coverTop, r: [top, top, r, r] };
    }
    // false = blank plate (lower layers of a collapsed stack).
    property bool showContent: true
    property bool interactive: true
    // 0 = front tile; 1..n = plates behind it (darker).
    property int plateLevel: 0
    // Group counter shown on the avatar (collapsed stack front tile).
    property int groupCount: 0
    // Tile height without the panel (group cardH).
    property real baseHeight: 84
    property bool actionable: false
    property string stage: ""
    property bool pulling: false
    property real pull: 0
    // Target growth (live while pulling): the group sums it, not the
    // animated height.
    readonly property real extraHeight: root.actionable ? actions.extraFor(root.pulling, root.pull) : 0
    readonly property real pullThreshold: root.cfg?.flowPullThreshold ?? 36

    signal tapped
    signal dismissRequested
    signal closeRequested
    signal stageRequested(string stage)

    readonly property real swipeDistance: root.cfg?.centerSwipeDistance ?? 80
    readonly property real closeDistance: 30
    property real dragX: 0
    // Animated plateLevel: the plate colour eases into the tile colour as
    // the stack fans out instead of snapping.
    property real plateShade: root.plateLevel
    Behavior on plateShade { Spring { eps: 0.01 } }
    property bool leaving: false

    // The fly-out landed: hand over (once) to the owner.
    onDragXChanged: {
        if (root.leaving && root.dragX <= -root.width) {
            root.leaving = false;
            root.dismissRequested();
        }
    }

    function dismiss(): void {
        root.leaving = true;
        root.dragX = -root.width - 40;
    }

    Behavior on dragX {
        enabled: !ma.pressed
        Spring { stiffness: 5; damp: 0.45 }
    }

    Item {
        id: tile
        x: root.dragX
        width: root.width
        height: root.height
        // Fades while dragged away, so a dismissal reads as "thrown out".
        opacity: 1 - Math.min(0.6, Math.abs(root.dragX) / (root.width * 1.5))

        // Surface, cut below coverTop (see NotificationGroup).
        Item {
            y: root.coverTop
            width: parent.width
            height: Math.max(0, parent.height - root.coverTop)
            clip: root.coverTop > 0

            Rectangle {
                readonly property color base: Qt.darker(root.theme?.qsCardBg ?? "#000000", 1 + 0.12 * root.plateShade)
                y: -root.coverTop
                width: tile.width
                height: tile.height
                radius: 20
                color: root.frost?.surface(base) ?? base
            }
        }

        NotificationCard {
            x: 12
            y: 12
            width: parent.width - 28
            height: root.baseHeight - 24
            notif: root.entry
            cfg: root.cfg
            groupCount: root.groupCount
            opacity: root.showContent ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        pressAndHoldInterval: root.cfg?.flowLongPressMs ?? 450

        property bool held: false
        property real pressX: 0
        property real pressY: 0
        property string axis: ""
        property bool fired: false

        onPressed: mouse => {
            pressX = mouse.x;
            pressY = mouse.y;
            axis = "";
            fired = false;
            held = false;
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            const dx = mouse.x - pressX;
            const dy = mouse.y - pressY;
            if (axis === "" && !held) {
                if (Math.abs(dx) > 8 && Math.abs(dx) > Math.abs(dy))
                    axis = "x";
                else if (Math.abs(dy) > 8)
                    axis = "y";
            }
            if (axis === "x") {
                // Left follows the cursor; right is rubber-banded.
                root.dragX = dx < 0 ? dx : dx * 0.25;
            } else if (axis === "y") {
                // Down (or back up while open) = pull the panel; up on a
                // closed tile = close the module.
                if (root.actionable && (dy > 0 || root.stage !== "")) {
                    root.pulling = true;
                    root.pull = dy;
                } else if (!fired && dy < -root.closeDistance) {
                    fired = true;
                    root.closeRequested();
                }
            }
        }
        onPressAndHold: {
            if (axis !== "" || !root.actionable)
                return;
            held = true;
            root.stageRequested(root.entry?.canReply ? "reply" : "actions");
        }
        onReleased: {
            if (root.pulling) {
                if (root.stage === "" && root.pull > root.pullThreshold)
                    root.stageRequested("actions");
                else if (root.stage !== "" && root.pull < -root.pullThreshold)
                    root.stageRequested("");
                root.pulling = false;
                root.pull = 0;
            } else if (axis === "x") {
                if (-root.dragX > root.swipeDistance)
                    root.dismiss();
                else
                    root.dragX = 0;
            } else if (axis === "" && !held) {
                root.tapped();
            }
        }
        onCanceled: {
            root.dragX = 0;
            root.pulling = false;
            root.pull = 0;
        }
    }

    // Context panel (above the gesture area: its buttons take presses).
    NotificationActions {
        id: actions
        x: root.dragX + 12
        y: root.baseHeight - 12 + actions.spacing
        width: root.width - 24
        entry: root.entry
        cfg: root.cfg
        theme: root.theme
        frost: root.frost
        stage: root.actionable ? root.stage : ""
        opacity: actions.reveal * tile.opacity
        reveal: Math.max(0, Math.min(1, (root.height - root.baseHeight) / actions.panelExtra))
        onStageRequested: s => root.stageRequested(s)
        onFinished: root.stageRequested("")
    }

    // Hover × (macOS-style, top-left corner over the tile rim).
    Rectangle {
        x: tile.x - 4
        y: -4
        width: 22
        height: 22
        radius: 11
        readonly property color base: closeMa.containsMouse ? "#4A4A4E" : "#2C2C2E"
        color: root.frost?.layerColor(base) ?? base
        border.width: 1
        border.color: root.frost?.layerColor("#3A3A3C") ?? "#3A3A3C"
        opacity: root.interactive && root.showContent && (ma.containsMouse || closeMa.containsMouse) && !ma.pressed ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }

        Text {
            anchors.centerIn: parent
            text: "✕"
            font.pixelSize: 10
            color: "#C7CBD3"
        }
        MouseArea {
            id: closeMa
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.dismiss()
        }
    }
}
