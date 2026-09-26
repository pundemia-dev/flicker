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
    // Full-height hover box (matches the tallest indicator, the music cover):
    // an 8px-tall HoverHandler needs pixel-perfect aim and flickers when the
    // cursor drifts a pixel up/down while reading the label.
    readonly property int boxHeight: cfg?.musicCoverDiameter ?? 24
    readonly property real labelMax: cfg?.micLabelMaxWidth ?? 120
    readonly property bool hovered: hover.hovered
    // Natural label width measured OUTSIDE the label item (TextMetrics):
    // reading appLabel.implicitWidth while the label itself is width-capped
    // feeds the animated box width back into extraWidth, so the target keeps
    // moving under the spring and the island background lags behind.
    readonly property real labelNaturalWidth: labelMetrics.advanceWidth
    // Width the hover label adds on top of the dot (drives island expansion).
    readonly property real extraWidth: active && hovered
        ? Math.min(labelMax, labelNaturalWidth + 8)
        : 0
    // Width used by the eviction math (stable: never depends on `evicted`,
    // otherwise hide->refit->unhide would oscillate).
    readonly property real desiredWidth: active ? diameter + extraWidth : 0

    width: evicted ? 0 : desiredWidth
    height: boxHeight
    visible: width > 0.5
    opacity: active ? 1 : 0
    // Width spring stays: the island target is built from stable widths
    // (stableRowWidth), so this spring and the island spring start on the
    // same frame with identical params and run the same curve — the clock
    // glides with the content in one motion (siblings, not series).
    Behavior on width { Spring {} }
    Behavior on opacity { NumberAnimation { duration: 140 } }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: root.diameter
        height: root.diameter
        radius: width / 2
        color: root.theme?.accentOrange ?? "#E58B4D"
    }

    TextMetrics {
        id: labelMetrics
        font.pixelSize: root.theme?.fontSizeIndicator ?? 11
        text: root.appName
    }

    Text {
        id: appLabel
        anchors.left: parent.left
        anchors.leftMargin: root.diameter + 6
        anchors.verticalCenter: parent.verticalCenter
        // Capped to the FINAL box width (extraWidth jumps instantly, the box
        // spring animates under it): the text fades in whole while the island
        // grows behind it, exactly like the uncapped version. Capping to the
        // animated root.width instead would reveal the text letter-by-letter.
        // The full-size target comes from labelMetrics — never from this
        // item's own implicitWidth (feedback loop: the island lags).
        width: Math.min(labelMetrics.advanceWidth, Math.max(0, root.extraWidth - 6))
        elide: Text.ElideRight
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
