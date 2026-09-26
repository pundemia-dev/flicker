import QtQuick
import "../components"

// Dictation indicator: stylized audio wave. Appears via fade + width growth
// from its left anchor while the island expands alongside it (desiredWidth
// feeds Island.islandWidth). Position: after music, before the clock.
Item {
    id: root
    // Plain (not required): Loader creates the item before onLoaded injects
    // the services bundle, and all reads below are null-safe.
    property var services: null
    property bool evicted: false

    readonly property var dictation: services?.dictation ?? null
    readonly property var theme: services?.theme ?? null
    readonly property var cfg: services?.cfg ?? null
    readonly property bool active: dictation?.active ?? false
    readonly property real waveWidth: cfg?.waveWidth ?? 28
    // Stable width for the eviction math (never depends on `evicted`).
    readonly property real desiredWidth: active ? waveWidth : 0

    width: evicted ? 0 : desiredWidth
    height: 14
    visible: width > 0.5
    opacity: active && !evicted ? 1 : 0
    Behavior on width { Spring {} }
    Behavior on opacity { NumberAnimation { duration: 160 } }

    Repeater {
        model: 4
        Rectangle {
            width: 3
            height: 6 + ((index + phase.phase) % 3) * 3
            radius: 1
            color: root.theme?.waveColor ?? "#A8C1FF"
            x: index * 6
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    QtObject {
        id: phase
        property int phase: 0
    }

    Timer {
        interval: 120
        repeat: true
        running: root.active
        onTriggered: phase.phase = (phase.phase + 1) % 3
    }
}
