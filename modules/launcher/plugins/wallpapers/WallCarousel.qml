import QtQuick
import Quickshell
import "../../../../components"
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

    // "d " view caption line: place in the group, resolution, file size.
    function dupeDetail(path: string): string {
        const d = root.plugin.wallpaper?.dupes.info[path];
        if (!d)
            return "";
        const parts = [I18n.tr("%1 of %2").arg(d.index).arg(d.count)];
        if (d.w > 0)
            parts.push(d.w + "×" + d.h);
        if (d.bytes > 0)
            parts.push(d.bytes >= 1048576 ? I18n.tr("%1 MB").arg((d.bytes / 1048576).toFixed(1)) : I18n.tr("%1 KB").arg(Math.round(d.bytes / 1024)));
        return parts.join(" · ");
    }
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

    // Ghosts of removed cards: dissolve where they were (below the rest,
    // which close the gap over them).
    Repeater {
        model: root.plugin.leavingModel

        WallCard {
            required property var modelData
            z: -1
            entry: modelData.entry
            d: modelData.d
            c: root.c
            lc: root.lc
            theme: root.theme
            service: root.service
            leaving: true
            favourite: root.plugin.wallpaper?.favouriteSet[modelData.entry.path] ?? false
            enabled: false
        }
    }

    Repeater {
        model: windowModel

        WallCard {
            id: card
            required property var modelData
            readonly property int idx: root.plugin.indexOf[modelData.path] ?? 0

            Component.onCompleted: {
                const v = root.plugin.flip[modelData.path];
                if (v !== undefined)
                    card.jumpShift(v);
            }
            Connections {
                target: root.plugin
                function onFlipNonceChanged(): void {
                    const v = root.plugin.flip[card.modelData.path];
                    if (v !== undefined)
                        card.jumpShift(v);
                }
            }

            entry: modelData
            instant: !!root.plugin.flipInstant[modelData.path]
            d: idx - root.plugin.pos + shift
            c: root.c
            lc: root.lc
            theme: root.theme
            service: root.service
            playing: root.plugin.playing && idx === root.plugin.selected
            favourite: root.plugin.wallpaper?.favouriteSet[modelData.path] ?? false
            detail: root.plugin.filter.filter === "dupes" ? root.dupeDetail(modelData.path) : ""
            onClicked: {
                if (idx === root.plugin.selected)
                    root.plugin.apply(modelData, false);
                else
                    root.plugin.select(idx);
            }
        }
    }

    // Status pills over the carousel top: hidden-files view (Ctrl+H),
    // slideshow (Ctrl+S).
    Row {
        z: 1001
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: root.c.badgeInset ?? 8
        spacing: 6

        WallPill {
            theme: root.theme
            c: root.c
            lc: root.lc
            shown: root.plugin.visibility !== "normal"
            glyph: root.plugin.visibility === "only" ? "\uecf0" : "\uea9a" // tabler eye-off / eye
            text: root.plugin.visibility === "only" ? I18n.tr("Hidden only") : I18n.tr("With hidden")
        }
        WallPill {
            theme: root.theme
            c: root.c
            lc: root.lc
            shown: root.plugin.filter.filter === "dupes" && (root.plugin.wallpaper?.dupes.busy ?? false)
            glyph: "\ueb1c" // tabler search
            text: I18n.tr("Looking for duplicates…")
        }
        WallPill {
            theme: root.theme
            c: root.c
            lc: root.lc
            shown: root.plugin.semanticBusy && (root.plugin.filter.filter === "semantic" || root.plugin.filter.filter === "similar")
            glyph: "\ueb1c" // tabler search
            text: I18n.tr("Searching…")
        }
        WallPill {
            theme: root.theme
            c: root.c
            lc: root.lc
            shown: (root.plugin.filter.filter === "semantic" || root.plugin.filter.filter === "similar")
                && (root.plugin.wallpaper?.semantic.indexing ?? false)
            glyph: "\uf6d7" // tabler sparkles
            text: I18n.tr("Indexing %1 / %2").arg(root.plugin.wallpaper?.semantic.done ?? 0).arg(root.plugin.wallpaper?.semantic.total ?? 0)
        }
        WallPill {
            theme: root.theme
            c: root.c
            lc: root.lc
            shown: root.plugin.wallpaper?.slideshow.active ?? false
            glyph: "\uebc9" // tabler slideshow
            text: I18n.tr("Slideshow · %1").arg(I18n.tr("%1 min").arg(Math.max(1, Math.round((root.c.slideshowIntervalSec ?? 900) / 60))))
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
    // its `orientation`, which dropped pure horizontal swipes. Mouse wheel
    // = vertical only (120 per card), touchpad = horizontal only
    // (touchpadStep per card, accelerated — touchpadGain). Qt on Wayland reports the touchpad as a Mouse
    // device; finger scrolling is recognised by a scroll phase or a pixel
    // delta, and anything within touchpadHoldMs of such an event belongs to
    // the same gesture (slow motion rounds pixelDelta to 0).
    property real touchpadAt: 0

    // Touchpad acceleration: events come at a steady rate, so the per-event
    // delta is the finger speed. Up to touchpadAccelFrom it counts 1:1 (slow,
    // precise), past it the gain grows by touchpadAccel per accelFrom of
    // extra speed, capped at touchpadAccelMax.
    function touchpadGain(dx: real): real {
        const from = Math.max(1, root.c.touchpadAccelFrom ?? 30);
        const extra = Math.max(0, Math.abs(dx) - from) / from;
        return Math.min(root.c.touchpadAccelMax ?? 3, 1 + (root.c.touchpadAccel ?? 1) * extra);
    }
    MouseArea {
        anchors.fill: parent
        z: 1000 // above the cards (z up to 100); presses fall through
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            const now = Date.now();
            const phase = wheel.phase ?? Qt.NoScrollPhase;
            if (phase !== Qt.NoScrollPhase || wheel.pixelDelta.x !== 0 || wheel.pixelDelta.y !== 0)
                root.touchpadAt = now;
            const touchpad = now - root.touchpadAt < (root.c.touchpadHoldMs ?? 150);
            if (touchpad)
                root.plugin.wheel(wheel.angleDelta.x * root.touchpadGain(wheel.angleDelta.x), root.c.touchpadStep ?? 200);
            else
                root.plugin.wheel(wheel.angleDelta.y, 120);
        }
    }
}
