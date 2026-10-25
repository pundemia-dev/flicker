import QtQuick
import "../../components"
import "../../config"
import "SettingsDisplays.js" as DisplaySettings

// Arrangement card of Settings → Displays: every enabled output as a rect
// at its logical position, scaled to fit. Drag one to move it (on release
// it snaps edge to edge: services/Displays.place), tap it for its page.
// Pending edits show at once; the rects spring to new places.
Item {
    id: root
    required property var host
    required property var theme
    readonly property var displays: root.host.displays
    readonly property real pad: 24
    implicitHeight: 240

    readonly property var rects: root.displays?.layout() ?? []
    readonly property var box: {
        if (root.rects.length === 0)
            return { x: 0, y: 0, w: 1, h: 1 };
        const x0 = Math.min(...root.rects.map(r => r.x)), y0 = Math.min(...root.rects.map(r => r.y));
        const x1 = Math.max(...root.rects.map(r => r.x + r.w)), y1 = Math.max(...root.rects.map(r => r.y + r.h));
        return { x: x0, y: y0, w: Math.max(1, x1 - x0), h: Math.max(1, y1 - y0) };
    }
    readonly property real k: Math.min((root.width - 2 * root.pad) / root.box.w, (root.height - 2 * root.pad) / root.box.h)
    readonly property real ox: (root.width - root.box.w * root.k) / 2
    readonly property real oy: (root.height - root.box.h * root.k) / 2

    function tint(c: color, a: real): color {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // A count model: the delegates stay while the rects only move.
    Repeater {
        model: root.rects.length

        Rectangle {
            id: del
            required property int index
            readonly property var r: root.rects[del.index] ?? null
            property bool dragging: false
            property real dragX: 0
            property real dragY: 0
            readonly property real homeX: root.ox + ((del.r?.x ?? 0) - root.box.x) * root.k
            readonly property real homeY: root.oy + ((del.r?.y ?? 0) - root.box.y) * root.k

            x: del.dragging ? del.dragX : del.homeX
            y: del.dragging ? del.dragY : del.homeY
            width: Math.max(8, (del.r?.w ?? 0) * root.k - 2)
            height: Math.max(8, (del.r?.h ?? 0) * root.k - 2)
            z: del.dragging ? 1 : 0
            Behavior on x { enabled: !del.dragging; Spring { stiffness: 6; damp: 0.6; eps: 0.3 } }
            Behavior on y { enabled: !del.dragging; Spring { stiffness: 6; damp: 0.6; eps: 0.3 } }
            Behavior on width { Spring { stiffness: 6; damp: 0.6; eps: 0.3 } }
            Behavior on height { Spring { stiffness: 6; damp: 0.6; eps: 0.3 } }

            radius: 6
            color: root.tint(root.theme.qsBlue, del.dragging ? 0.34 : area.containsMouse ? 0.26 : 0.18)
            border.width: 1.5
            border.color: del.dragging || area.containsMouse ? root.theme.qsBlue : root.tint(root.theme.islandFg, 0.22)

            Column {
                anchors.centerIn: parent
                width: parent.width - 12
                spacing: 2
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: del.r?.label ?? ""
                    color: root.theme.islandFg
                    font.family: root.theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: del.r ? `${del.r.w} × ${del.r.h}` : ""
                    color: root.theme.settingsSecondary
                    font.family: root.theme.fontFamily
                    font.pixelSize: 11
                }
            }

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: del.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                property point start
                property real sx: 0
                property real sy: 0

                onPressed: m => {
                    area.start = area.mapToItem(root, m.x, m.y);
                    area.sx = del.x;
                    area.sy = del.y;
                }
                onPositionChanged: m => {
                    if (!area.pressed)
                        return;
                    const p = area.mapToItem(root, m.x, m.y);
                    const dx = p.x - area.start.x, dy = p.y - area.start.y;
                    if (!del.dragging && Math.hypot(dx, dy) < 4)
                        return;
                    del.dragX = area.sx + dx;
                    del.dragY = area.sy + dy;
                    del.dragging = true;
                }
                onReleased: {
                    const name = del.r?.name ?? "";
                    if (del.dragging) {
                        root.displays.place(name, root.box.x + (del.dragX - root.ox) / root.k, root.box.y + (del.dragY - root.oy) / root.k);
                        del.dragging = false;
                        return;
                    }
                    const o = root.displays.find(name);
                    if (o)
                        root.host.push(DisplaySettings.page(root.displays, o), "");
                }
                onCanceled: del.dragging = false
            }
        }
    }
}
