import QtQuick
import "../components"
import "glyphs"

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
    // A new event object = a fresh glyph (its reveal replays even when the
    // same glyph follows itself, e.g. caffeine on -> off); an in-place
    // update of the same key keeps the running animation.
    // A NEW event = coming out of the gap (live was null) or another key;
    // only an in-place update (same key while showing) keeps the glyph.
    // Comparing keys alone missed two same-key events in a row: the item
    // outlives the short gap, so the second one showed the first's glyph
    // mid-loop (already cracked) with no appearance at all.
    property bool glyphFresh: true
    property bool hadLive: false
    onLiveChanged: {
        if (live) {
            const fresh = !hadLive || (ev?.key ?? "") !== (live.key ?? "");
            ev = live;
            if (fresh) {
                glyphFresh = false;
                Qt.callLater(() => root.glyphFresh = true);
            }
        }
        hadLive = live !== null;
    }
    property bool entered: false
    Component.onCompleted: {
        ev = live;
        hadLive = live !== null;
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
        id: fade
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
        // Animated drawn glyph (event `glyph`: name in `glyphs`; optional
        // `glyphArgs` -> item.args); recreated per event (glyphFresh).
        Loader {
            anchors.fill: parent
            active: root.glyphFresh
            sourceComponent: root.glyphComp
            onLoaded: {
                item.size = Qt.binding(() => root.glyphSize);
                item.color = Qt.binding(() => root.tint);
                if ("args" in item)
                    item.args = root.ev?.glyphArgs ?? {};
                if ("theme" in item)
                    item.theme = Qt.binding(() => root.theme);
                // Glyphs start their reveal only once the icon has faded in
                // enough (`eventGlyphStartAt` of the fade): a fresh icon
                // fades in from 0 under blur and swallowed short reveals.
                if ("ready" in item)
                    item.ready = Qt.binding(() => fade.p >= (root.cfg?.eventGlyphStartAt ?? 0.8));
                if ("rimTop" in item) {
                    item.rimTop = Qt.binding(() => root.theme?.glyphRimTop ?? "#40FFFFFF");
                    item.rimBottom = Qt.binding(() => root.theme?.glyphRimBottom ?? "#1AFFFFFF");
                }
            }
        }
    }

    // `color` = a Theme colour name, or a function returning one (live:
    // the charger events follow the battery level like the right arc).
    readonly property string toneName: {
        const c = root.ev?.color ?? "islandFg";
        return typeof c === "function" ? `${c()}` : `${c}`;
    }
    readonly property color tint: root.theme?.[root.toneName] ?? root.theme?.islandFg ?? "#E9ECF1"
    // Drawn glyphs by name (indicators/glyphs/GlyphRegistry.qml).
    GlyphRegistry { id: glyphRegistry }
    readonly property var glyphComp: glyphRegistry.map[root.ev?.glyph ?? ""] ?? null
}
