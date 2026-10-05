import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../components"

// Tray view of the stash module: file grid (cfg.columns wide, island grows
// up to cfg.rowsMax rows, wheel-scrolls past that — no Flickable, it would
// grab presses and break the swipe-up close) + action row (refresh, open
// folder, send all, LocalSend receive toggle | clear all).
Item {
    id: root
    required property var stash
    required property var localSend
    required property var cfg
    required property var theme
    required property real tileRadius
    signal sendRequested(var files)

    readonly property real actionsH: root.cfg.actionsHeight

    Item {
        id: viewport
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: actionRow.top
        anchors.bottomMargin: root.cfg.gap
        clip: true

        readonly property real maxScroll: Math.max(0, grid.height - viewport.height)
        property real scroll: 0
        onMaxScrollChanged: viewport.scroll = Math.min(viewport.scroll, viewport.maxScroll)

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 2;
                viewport.scroll = Math.max(0, Math.min(viewport.maxScroll, viewport.scroll - delta));
            }
        }

        Grid {
            id: grid
            y: -scrollY
            columns: root.cfg.columns
            spacing: root.cfg.gap

            property real scrollY: viewport.scroll
            Behavior on scrollY { Spring { stiffness: 6; damp: 0.6 } }

            Repeater {
                model: root.stash.model

                StashTile {
                    width: root.cfg.cellSize
                    height: root.cfg.cellSize
                    stash: root.stash
                    localSend: root.localSend
                    cfg: root.cfg
                    theme: root.theme
                    radius: root.tileRadius
                    onSendRequested: files => root.sendRequested(files)
                }
            }
        }

        // Empty state.
        Column {
            anchors.centerIn: parent
            spacing: 4
            visible: root.stash.count === 0

            IconImage {
                anchors.horizontalCenter: parent.horizontalCenter
                implicitSize: 36
                source: Quickshell.iconPath("folder-open", "folder")
                asynchronous: true
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Лоток пуст"
                color: root.theme.islandFg
                font.pixelSize: root.theme.fontSizeClock
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Перетащите файл на остров"
                color: root.theme.subtleFg
                font.pixelSize: root.theme.fontSizeBody
            }
        }
    }

    Item {
        id: actionRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.actionsH

        Row {
            spacing: root.cfg.gap
            height: parent.height

            IconButton {
                theme: root.theme
                width: root.actionsH
                height: root.actionsH
                glyph: ""
                onClicked: root.stash.refresh()
            }
            IconButton {
                theme: root.theme
                width: root.actionsH
                height: root.actionsH
                glyph: ""
                onClicked: root.stash.openFolder()
            }
            IconButton {
                theme: root.theme
                width: root.actionsH
                height: root.actionsH
                visible: root.localSend.enabled
                disabled: root.stash.count === 0
                glyph: ""
                onClicked: root.sendRequested(root.stash.allPaths())
            }
            // LocalSend receive server on/off (session toggle).
            IconButton {
                theme: root.theme
                width: root.actionsH
                height: root.actionsH
                visible: root.localSend.enabled
                checked: root.localSend.receiving
                glyph: ""
                onClicked: root.localSend.receiving = !root.localSend.receiving
            }
        }

        Text {
            anchors.centerIn: parent
            visible: root.stash.count > 0
            text: root.stash.count + " " + root.plural(root.stash.count)
            color: root.theme.subtleFg
            font.pixelSize: root.theme.fontSizeBody
        }

        IconButton {
            anchors.right: parent.right
            theme: root.theme
            width: root.actionsH
            height: root.actionsH
            disabled: root.stash.count === 0
            glyph: ""
            onClicked: root.stash.clearAll()
        }
    }

    function plural(n: int): string {
        const m10 = n % 10, m100 = n % 100;
        if (m10 === 1 && m100 !== 11)
            return "файл";
        if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14))
            return "файла";
        return "файлов";
    }
}
