import QtQuick
import Quickshell
import "../../components"

// The lock clock, flown out of the island (user, Oct 2026): starts exactly on
// the bar's clock label (`home` = Island.lockClock(), snapshot at lock time)
// at the bar's size — drawn at the final size and scaled down, so the flight
// is one scale spring, no relayout — and blur-fades in there while the
// field's bar crop blur-fades out (a crossfade on the spot), then its centre
// and scale spring to `slot` (the column placeholder). `out = false` = back
// into the bar: it lands, fades into the returning crop, `arrivedHome`.
// No home (bar hidden: Minimal / module) = it just blur-fades in at the slot.
Item {
    id: root

    required property var cfg
    property var home: null
    property rect slot: Qt.rect(0, 0, 0, 0)
    property bool out: false
    property color color: "#EDF1F8"

    signal arrivedHome

    readonly property real finalPx: root.cfg.clockFontSize ?? 64
    readonly property alias text: label.text
    readonly property string family: root.home?.family ?? Qt.application.font.family
    readonly property real homeScale: root.home ? root.home.pixelSize / root.finalPx : 1
    readonly property real homeCx: root.home ? root.home.x + root.home.width / 2 : 0
    readonly property real homeCy: root.home ? root.home.y + root.home.height / 2 : 0

    // Centre + scale: plain targets, set imperatively (never read animated).
    property bool animate: false
    property real cx: root.homeCx
    property real cy: root.homeCy
    property real s: root.homeScale
    Behavior on cx { enabled: root.animate; Spring { stiffness: root.cfg.clockStiffness ?? 3; damp: root.cfg.clockDamping ?? 0.45 } }
    Behavior on cy { enabled: root.animate; Spring { stiffness: root.cfg.clockStiffness ?? 3; damp: root.cfg.clockDamping ?? 0.45 } }
    Behavior on s { enabled: root.animate; Spring { stiffness: root.cfg.clockStiffness ?? 3; damp: root.cfg.clockDamping ?? 0.45; eps: 0.002 } }

    width: label.implicitWidth
    height: label.implicitHeight
    x: root.cx - root.width / 2
    y: root.cy - root.height / 2
    scale: Math.max(0.01, root.s)

    readonly property bool atSlot: root.out && Math.abs(root.cx - (root.slot.x + root.slot.width / 2)) < 1
        && Math.abs(root.cy - (root.slot.y + root.slot.height / 2)) < 1 && Math.abs(root.s - 1) < 0.01 && fade.p > 0.99
    readonly property bool atHome: root.home !== null && Math.abs(root.cy - root.homeCy) < 1 && Math.abs(root.s - root.homeScale) < 0.01

    function place(cx: real, cy: real, s: real, animated: bool): void {
        root.animate = animated;
        root.cx = cx;
        root.cy = cy;
        root.s = s;
    }

    onOutChanged: {
        if (root.out) {
            launch.restart();
        } else {
            launch.stop();
            if (root.home)
                root.place(root.homeCx, root.homeCy, root.homeScale, true);
            homeCheck.restart();
        }
    }

    Timer {
        id: launch
        interval: root.cfg.clockDelayMs ?? 0
        onTriggered: root.place(root.slot.x + root.slot.width / 2, root.slot.y + root.slot.height / 2, 1, root.home !== null)
    }

    Timer {
        id: homeCheck
        interval: 50
        repeat: true
        onTriggered: if (fade.p < 0.01) {
            homeCheck.stop();
            root.arrivedHome();
        }
    }

    SystemClock {
        id: clk
        precision: SystemClock.Minutes
    }

    FadeBlur {
        id: fade
        anchors.fill: parent
        // On the spot it crossfades with the bar crop; in flight it shows.
        shown: root.out || (root.home !== null && !root.atHome)

        Text {
            id: label
            text: Qt.formatDateTime(clk.date, "hh:mm")
            color: root.color
            font.pixelSize: root.finalPx
            font.family: root.family
            // The bar's weight near home, the lock's once half way out.
            font.weight: root.home && root.s < (root.homeScale + 1) / 2 ? root.home.weight : Font.Light
            renderType: Text.CurveRendering
        }
    }
}
