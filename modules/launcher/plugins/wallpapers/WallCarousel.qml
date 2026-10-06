import QtQuick
import Quickshell
import "../../../../config"
import "CarouselMath.js" as M

// Carousel body (drawn from WallpapersModule state). Only a WINDOW of cards
// around the centre exists — the folder may hold thousands of files — fed
// through a ScriptModel over the plugin's stable entry objects, so cards
// that stay in the window keep their delegate while it shifts.
Item {
    id: root
    required property var plugin
    required property var service
    required property var theme
    required property var c
    required property var lc

    clip: true

    readonly property int centre: Math.round(root.plugin.pos)
    readonly property int reach: M.reach(root.c, root.width / 2)

    ScriptModel {
        id: windowModel
        values: {
            const list = root.plugin.entries;
            const lo = Math.max(0, root.centre - root.reach);
            const hi = Math.min(list.length, root.centre + root.reach + 1);
            return list.slice(lo, hi);
        }
    }

    Repeater {
        model: windowModel

        WallCard {
            required property var modelData
            readonly property int idx: root.plugin.indexOf[modelData.path] ?? 0

            entry: modelData
            d: idx - root.plugin.pos
            c: root.c
            lc: root.lc
            theme: root.theme
            service: root.service
            playing: root.plugin.playing && idx === root.plugin.selected
            onClicked: {
                if (idx === root.plugin.selected)
                    root.plugin.apply(modelData, false);
                else
                    root.plugin.select(idx);
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.service.loaded && root.plugin.entries.length === 0
        text: root.service.files.length === 0
            ? I18n.tr("No wallpapers in %1").arg((root.c.dirs ?? []).join(", "))
            : I18n.tr("Nothing found")
        color: root.theme.cardDim
        font.family: root.theme.fontFamily
        font.pixelSize: root.lc.fontSize
    }

    // Wheel / touchpad. A plain MouseArea (no buttons: card clicks pass
    // through) gets wheel events along BOTH axes — WheelHandler only sees
    // its `orientation`, which dropped pure horizontal swipes. The dominant
    // axis drives the carousel: a mouse wheel is vertical, a touchpad swipe
    // sideways is horizontal. Touchpad deltas (pixelDelta set) step per
    // touchpadStep, wheel notches per 120.
    property int debugLeft: 40
    MouseArea {
        anchors.fill: parent
        z: 1000 // above the cards (z up to 100); presses fall through
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            const dx = wheel.angleDelta.x, dy = wheel.angleDelta.y;
            const touchpad = wheel.pixelDelta.x !== 0 || wheel.pixelDelta.y !== 0;
            if (root.debugLeft > 0) {
                root.debugLeft--;
                console.log("[wallpapers] wheel", touchpad ? "touchpad" : "mouse", "angle", dx, dy, "pixel", wheel.pixelDelta.x, wheel.pixelDelta.y);
            }
            const delta = Math.abs(dx) > Math.abs(dy) ? dx : dy;
            root.plugin.wheel(delta, touchpad ? (root.c.touchpadStep ?? 120) : 120);
        }
    }
}
