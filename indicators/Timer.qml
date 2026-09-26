import QtQuick
import "../components"

// Timer indicator (right side). No timer service feeds it yet, so it stays
// inactive until `services.timer` exists (spec: planned indicator).
Rectangle {
    id: root
    // Plain (not required): Loader creates the item before onLoaded injects
    // the services bundle, and all reads below are null-safe.
    property var services: null
    property bool evicted: false
    signal requestOpen(string name, var payload)

    readonly property var timer: services?.timer ?? null
    readonly property var theme: services?.theme ?? null
    readonly property bool active: timer?.active ?? false
    readonly property string value: timer?.remainingText ?? "00:00"
    // Stable width for the eviction math (never depends on `evicted`).
    readonly property real desiredWidth: active ? 50 : 0

    width: evicted ? 0 : desiredWidth
    height: 20
    radius: 10
    color: root.theme?.islandBg ?? "#2C3139"
    opacity: active && !evicted ? 1 : 0
    visible: opacity > 0.01
    Behavior on width { Spring {} }
    Behavior on opacity { NumberAnimation { duration: 160 } }

    Text {
        anchors.centerIn: parent
        text: root.value
        color: root.theme?.islandFg ?? "#E5E9F0"
        font.pixelSize: root.theme?.fontSizeIndicator ?? 11
    }
}
