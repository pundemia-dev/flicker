import QtQuick
import "../../../components"
import ".."

// One iOS-style notification tile of the Notification Center: the shared
// NotificationCard on a rounded plate. Swipe left past centerSwipeDistance
// dismisses (the tile flies out, then `dismissRequested`), a tap emits
// `tapped`, hovering shows the × button.
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
    // false = blank plate (lower layers of a collapsed stack).
    property bool showContent: true
    property bool interactive: true
    // 0 = front tile; 1..n = plates behind it (darker).
    property int plateLevel: 0
    // Group counter shown on the avatar (collapsed stack front tile).
    property int groupCount: 0

    signal tapped
    signal dismissRequested
    signal closeRequested

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
                color: root.frost?.layerColor(base) ?? base
            }
        }

        NotificationCard {
            anchors.fill: parent
            anchors.margins: 12
            anchors.rightMargin: 16
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

        property real pressX: 0
        property real pressY: 0
        property string axis: ""
        property bool fired: false

        onPressed: mouse => {
            pressX = mouse.x;
            pressY = mouse.y;
            axis = "";
            fired = false;
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            const dx = mouse.x - pressX;
            const dy = mouse.y - pressY;
            if (axis === "") {
                if (Math.abs(dx) > 8 && Math.abs(dx) > Math.abs(dy))
                    axis = "x";
                else if (Math.abs(dy) > 8)
                    axis = "y";
            }
            if (axis === "x") {
                // Left follows the cursor; right is rubber-banded.
                root.dragX = dx < 0 ? dx : dx * 0.25;
            } else if (axis === "y" && !fired && dy < -root.closeDistance) {
                fired = true;
                root.closeRequested();
            }
        }
        onReleased: {
            if (axis === "x") {
                if (-root.dragX > root.swipeDistance)
                    root.dismiss();
                else
                    root.dragX = 0;
            } else if (axis === "") {
                root.tapped();
            }
        }
        onCanceled: root.dragX = 0
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
