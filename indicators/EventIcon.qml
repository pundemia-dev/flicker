import QtQuick
import "../components"

// Event indicator, LEFT half: the glyph of the visible event
// (services/Events.qml) at the far left of the bar row; EventText is its
// right half. Grows in with the island and blur-fades (FadeBlur), holds the
// last event while collapsing so the leaving glyph never blanks.
Item {
    id: root
    property var services: null
    property bool evicted: false

    readonly property var events: services?.events ?? null
    readonly property var theme: services?.theme ?? null
    readonly property var cfg: services?.cfg ?? null
    readonly property var live: events?.current ?? null
    readonly property bool active: live !== null
    property var ev: null
    onLiveChanged: if (live) ev = live
    property bool entered: false
    Component.onCompleted: {
        ev = live;
        entered = true;
    }

    readonly property int glyphSize: cfg?.eventIconSize ?? 18
    // Pressed against the island's left edge (event glyph only, user): the
    // glyph keeps the same gap to the left edge as to the top/bottom, so it
    // reaches `pull` px into the edge padding. The item is that much
    // narrower, so the island shrinks by it and the rest of the row stays
    // where it was. Built from config values only (never the live edgePad:
    // that reads this width back — binding loop).
    readonly property real edgeGap: ((services?.islandHeight ?? 36) - glyphSize) / 2
    readonly property real pull: Math.max(0, Math.min(glyphSize, (cfg?.edgePaddingMin ?? 16) - edgeGap))
    // Extra distance from the rest of the row (on top of the row spacing).
    readonly property real gap: cfg?.eventGap ?? 48
    readonly property real desiredWidth: active ? glyphSize - pull + gap : 0

    width: (entered && !evicted) ? desiredWidth : 0
    height: cfg?.musicCoverDiameter ?? 24
    Behavior on width { Spring {} }

    FadeBlur {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: -root.pull
        width: root.glyphSize
        height: root.glyphSize
        shown: root.active && !root.evicted

        Icon {
            anchors.fill: parent
            visible: root.glyphComp === null
            text: root.ev?.icon ?? ""
            font.family: (root.ev?.family ?? "") === "nerd" ? (root.theme?.nerdIconFamily ?? "") : (root.theme?.iconFamily ?? "tabler-icons")
            iconSize: root.glyphSize
            iconColor: root.tint
        }
        // Animated drawn glyph (event `glyph`: name in `glyphs`); a new
        // event with another glyph recreates it, so its reveal replays.
        Loader {
            anchors.fill: parent
            sourceComponent: root.glyphComp
            onLoaded: {
                item.size = Qt.binding(() => root.glyphSize);
                item.color = Qt.binding(() => root.tint);
                if ("eyeColor" in item)
                    item.eyeColor = Qt.binding(() => root.theme?.islandBg ?? "#000000");
            }
        }
    }

    readonly property color tint: root.theme?.[root.ev?.color ?? "islandFg"] ?? root.theme?.islandFg ?? "#E9ECF1"
    readonly property var glyphs: ({
            pacman: pacmanGlyph
        })
    readonly property var glyphComp: root.glyphs[root.ev?.glyph ?? ""] ?? null
    Component {
        id: pacmanGlyph
        PacmanGlyph {}
    }
}
