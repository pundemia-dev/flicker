import QtQuick
import "../components"

// Microphone indicator: orange dot on the island's left edge. On hover the
// consuming app's name fades in to the right and the island expands as the
// text appears (row width feeds Island.barFittedWidth). Not interactive.
Item {
    id: root
    // Plain (not required): Loader creates the item before onLoaded injects
    // the services bundle, and all reads below are null-safe.
    property var services: null
    property bool evicted: false

    readonly property var audio: services?.audio ?? null
    readonly property var theme: services?.theme ?? null
    readonly property var cfg: services?.cfg ?? null
    readonly property bool active: audio?.micActive ?? false
    readonly property string appName: audio?.micAppName ?? ""
    readonly property int diameter: cfg?.micDotDiameter ?? 8
    readonly property real labelMax: cfg?.micLabelMaxWidth ?? 120
    readonly property bool hovered: hover.hovered
    // Width the hover label adds on top of the dot (drives island expansion).
    readonly property real extraWidth: active && hovered
        ? Math.min(labelMax, appLabel.implicitWidth + 8)
        : 0
    // Width used by the eviction math (stable: never depends on `evicted`,
    // otherwise hide->refit->unhide would oscillate).
    readonly property real desiredWidth: active ? diameter + extraWidth : 0

    width: evicted ? 0 : desiredWidth
    height: diameter
    visible: width > 0.5
    opacity: active ? 1 : 0
    Behavior on width { Spring {} }
    Behavior on opacity { NumberAnimation { duration: 140 } }

    Rectangle {
        width: root.diameter
        height: root.diameter
        radius: width / 2
        color: root.theme?.accentOrange ?? "#E58B4D"
    }

    Text {
        id: appLabel
        anchors.left: parent.left
        anchors.leftMargin: root.diameter + 6
        anchors.verticalCenter: parent.verticalCenter
        text: root.appName
        color: root.theme?.islandFg ?? "#E2E7F1"
        font.pixelSize: root.theme?.fontSizeIndicator ?? 11
        opacity: root.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    // Hover only: presses fall through to the gesture layer below the bar.
    HoverHandler {
        id: hover
    }
}
