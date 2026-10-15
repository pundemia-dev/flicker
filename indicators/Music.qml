import QtQuick
import "../components"

// Music + timer indicator: round album cover, and while a timer runs its
// ring (TimerHalo) around the cover (`indicators.musicTimerRing`; the
// stand-alone TimerRing is then unused). ONE item for both, so a player
// coming / going only grows / shrinks the cover inside the ring (the ring
// springs between "around the cover" and its stand-alone size) instead of
// one indicator leaving and another arriving.
// Music only: click or hover opens the player. With the ring: hover no
// longer opens it (a press could not reach the cover) — tap = player, press
// + drag down = timer; without a player a tap opens the timer.
// Collapses smoothly when evicted for space.
Item {
    id: root
    // Plain (not required): Loader creates the item before onLoaded injects
    // the services bundle, and all reads below are null-safe.
    property var services: null
    property bool evicted: false
    signal requestOpen(string name, var payload)

    readonly property var players: services?.players ?? null
    readonly property var theme: services?.theme ?? null
    readonly property var cfg: services?.cfg ?? null
    readonly property var countdown: services?.countdown ?? null
    readonly property bool hasMusic: root.players?.musicActive ?? false
    readonly property int diameter: cfg?.musicCoverDiameter ?? 24
    readonly property string artUrl: players?.artUrl ?? ""
    readonly property bool timerOn: (root.countdown?.active ?? false) && (root.cfg?.musicTimerRing ?? true)
        && !(root.services?.timerInDrop ?? false)
    readonly property real ringLine: root.cfg?.timerRingLine ?? 2.5
    // With the ring the pair keeps the plain cover's size (user): the ring's
    // outer edge = the cover's edge without a timer, the cover shrinks
    // inside it by the gap + line.
    readonly property real coverTarget: root.timerOn
        ? root.diameter - 2 * ((root.cfg?.musicTimerRingGap ?? 1.5) + root.ringLine) : root.diameter
    // Ring box: the plain cover's size, or the stand-alone ring without a player.
    readonly property real ringTarget: root.hasMusic ? root.diameter : (root.cfg?.timerRingSize ?? 18)
    readonly property Item halo: haloItem
    // Stable width for the eviction math (never depends on `evicted`).
    readonly property real desiredWidth: root.timerOn ? root.ringTarget : (root.hasMusic ? root.diameter : 0)

    property real coverSize: root.coverTarget
    Behavior on coverSize { Spring {} }
    property real ringSize: root.ringTarget
    Behavior on ringSize { Spring {} }
    // Cover in / out (player appears / closes) without touching the ring.
    property real coverIn: root.hasMusic ? 1 : 0
    Behavior on coverIn { Spring { stiffness: 4; damp: 0.5; eps: 0.005 } }

    // Shared element contract (core/TransitionLayer): the cover flies into
    // the player module's "cover" slot, morphing to the slot's radius.
    readonly property Item sharedElement: cover
    readonly property var sharedTransition: ({
            target: "player",
            slot: "cover",
            properties: { radius: "slot" },
            curve: "spring"
        })
    readonly property Item sharedHome: coverBox
    function restoreShared(): void {
        cover.anchors.fill = coverBox;
        cover.radius = Qt.binding(() => root.coverSize / 2);
    }

    // Enter animation (see Microphone.qml): grow in instead of popping.
    property bool entered: false
    Component.onCompleted: entered = true

    width: (entered && !evicted) ? desiredWidth : 0
    height: Math.max(root.diameter, root.ringSize)
    opacity: evicted ? 0 : 1
    Behavior on width { Spring {} }
    Behavior on opacity { NumberAnimation { duration: 160 } }

    // The cover: centred, never wider than the (entering) indicator.
    Rectangle {
        id: coverBox
        anchors.centerIn: parent
        width: Math.min(root.width, root.coverSize)
        height: root.coverSize
        radius: root.coverSize / 2
        color: root.theme?.islandBg ?? "#2B2F36"
        clip: true
        scale: 0.4 + 0.6 * Math.max(0, root.coverIn)
        opacity: Math.max(0, Math.min(1, root.coverIn))
        visible: opacity > 0.01

        RoundedImage {
            id: cover
            anchors.fill: parent
            source: root.artUrl
            // Max rounding: the art masked to a circle (Rectangle clip is
            // square-only, hence the MultiEffect mask).
            radius: root.coverSize / 2
        }

        Text {
            anchors.centerIn: parent
            text: "♫"
            color: root.theme?.islandFg ?? "#E8ECF4"
            font.pixelSize: Math.max(8, root.coverSize / 2)
            visible: !cover.ready
        }
    }

    TimerHalo {
        id: haloItem
        anchors.centerIn: parent
        width: Math.min(root.width, root.ringSize)
        height: width
        countdown: root.countdown
        theme: root.theme
        line: root.ringLine
        shown: root.timerOn
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        property real pressY: 0
        property bool dragged: false
        onPressed: mouse => {
            pressY = mouse.y;
            dragged = false;
        }
        onPositionChanged: mouse => {
            if (!pressed || dragged || !root.timerOn)
                return;
            if (mouse.y - pressY > (root.cfg?.musicTimerDragPx ?? 14)) {
                dragged = true;
                root.requestOpen("timer", { ring: haloItem });
            }
        }
        onClicked: {
            if (dragged)
                return;
            if (root.hasMusic)
                root.requestOpen("player", { shared: root });
            else if (root.timerOn)
                root.requestOpen("timer", { ring: haloItem });
        }
        onEntered: if (!root.timerOn && root.hasMusic)
            root.requestOpen("player", { shared: root })
    }
}
