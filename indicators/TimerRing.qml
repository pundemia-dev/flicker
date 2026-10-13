import QtQuick
import "../components"

// Timer indicator (far left of the bar row): a ring of the remaining time
// (services/Countdown) — the TimerHalo shared element, which unfolds into
// the module's perimeter on open and folds back on close. While a player
// shows, the halo goes around the music cover instead (Music.qml) and this
// indicator stays hidden (IndicatorLayout). Click = open the timer module.
Item {
    id: root
    property var services: null
    property bool evicted: false
    signal requestOpen(string name, var payload)

    readonly property var countdown: services?.countdown ?? null
    readonly property var theme: services?.theme ?? null
    readonly property var cfg: services?.cfg ?? null
    readonly property real size: root.cfg?.timerRingSize ?? 18
    readonly property bool active: root.countdown?.active ?? false
    // 0 once the timer ends: the width (and the ring with it) collapses,
    // then the Loader unloads (IndicatorLayout `collapsing`).
    readonly property real desiredWidth: root.active ? root.size : 0
    readonly property Item halo: haloItem

    property bool entered: false
    Component.onCompleted: entered = true
    width: (entered && !evicted) ? desiredWidth : 0
    height: root.size
    opacity: evicted ? 0 : 1
    Behavior on width { Spring {} }
    Behavior on opacity { NumberAnimation { duration: 160 } }

    // Square, centred, shrinks with the entering / leaving width.
    TimerHalo {
        id: haloItem
        anchors.centerIn: parent
        width: Math.min(root.width, root.size)
        height: width
        countdown: root.countdown
        theme: root.theme
        line: root.cfg?.timerRingLine ?? 2.5
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.requestOpen("timer", { ring: haloItem })
    }
}
