import QtQuick
import "../components"

// Music indicator: round album cover. Click or hover opens the player
// module (requestOpen). Collapses smoothly when evicted for space.
Rectangle {
    id: root
    // Plain (not required): Loader creates the item before onLoaded injects
    // the services bundle, and all reads below are null-safe.
    property var services: null
    property bool evicted: false
    signal requestOpen(string name, var payload)

    readonly property var players: services?.players ?? null
    readonly property var theme: services?.theme ?? null
    readonly property var cfg: services?.cfg ?? null
    readonly property int diameter: cfg?.musicCoverDiameter ?? 24
    readonly property string artUrl: players?.artUrl ?? ""
    // Stable width for the eviction math (never depends on `evicted`).
    readonly property real desiredWidth: diameter
    // Shared element contract (core/TransitionLayer): the cover flies into
    // the player module's "cover" slot, morphing to the slot's radius.
    readonly property Item sharedElement: cover
    readonly property var sharedTransition: ({
            target: "player",
            slot: "cover",
            properties: { radius: "slot" },
            curve: "spring"
        })
    function restoreShared(): void {
        cover.anchors.fill = root;
        cover.radius = Qt.binding(() => root.diameter / 2);
    }

    // Enter animation (see Microphone.qml): grow in instead of popping.
    property bool entered: false
    Component.onCompleted: entered = true

    width: (entered && !evicted) ? desiredWidth : 0
    height: diameter
    radius: diameter / 2
    color: root.theme?.islandBg ?? "#2B2F36"
    clip: true
    opacity: evicted ? 0 : 1
    Behavior on width { Spring {} }
    Behavior on opacity { NumberAnimation { duration: 160 } }

    RoundedImage {
        id: cover
        anchors.fill: parent
        source: root.artUrl
        // Max rounding: the art masked to a circle (Rectangle clip is
        // square-only, hence the MultiEffect mask).
        radius: root.diameter / 2
    }

    Text {
        anchors.centerIn: parent
        text: "♫"
        color: root.theme?.islandFg ?? "#E8ECF4"
        font.pixelSize: Math.max(8, root.diameter / 2)
        visible: !cover.ready
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.requestOpen("player", { shared: root })
        onEntered: root.requestOpen("player", { shared: root })
    }
}
