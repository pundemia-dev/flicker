import QtQuick
import "../../components"
import "../../config"

// Drop chooser (pShell stash design): opens when a file drag hovers the
// island. Two tiles side by side: the tray (no fill, dashed outline while
// the drag is over it) copies into the stash dir; LocalSend (tinted, tint
// rises on hover) skips the stash and goes straight to the device picker.
// Island owns the open/leave logic (Island.stashDrag*), this only reports
// `dragActive` and routes drops.
Item {
    id: root
    required property var payload
    required property var stash
    required property var localSend
    required property var cfg
    required property var theme
    required property real surfaceRadius
    signal closeRequested
    signal openRequested(string name, var payload)

    // Qt routes a drag to the topmost DropArea only; the island's own drop
    // area loses containsDrag while the drag sits over a tile, so the island
    // ORs this in (pShell `_localDragging`).
    readonly property bool dragActive: trayDrop.containsDrag || sendDrop.containsDrag
    readonly property real tileRadius: Math.max(4, root.surfaceRadius - root.cfg.padding)

    // Tray drop: back to the tray when the chooser replaced it, else close.
    function toTray(paths: var): void {
        root.stash.drop(paths);
        if ((root.payload?.returnView ?? "") === "tray")
            root.openRequested("stash", { view: "tray" });
        else
            root.closeRequested();
    }

    function toSend(paths: var): void {
        // Not started (an upload is running): keep the files in the tray
        // rather than losing the drop.
        if (!root.localSend.start(paths)) {
            root.toTray(paths);
            return;
        }
        root.openRequested("stash", { view: "send", returnView: root.payload?.returnView ?? "" });
    }

    Row {
        anchors.fill: parent
        anchors.margins: root.cfg.padding
        spacing: root.cfg.gap

        // ── Tray zone: transparent, dashed border while hovered ──
        Item {
            width: root.cfg.dropZoneWidth
            height: root.cfg.dropZoneHeight

            property real hot: trayDrop.containsDrag ? 1 : 0
            Behavior on hot { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }

            DashedRect {
                anchors.fill: parent
                strokeColor: root.theme.cardBlue
                strokeWidth: root.cfg.dashedBorderWidth
                dashLength: root.cfg.dashedBorderDashLength
                gapLength: root.cfg.dashedBorderGapLength
                cornerRadius: root.tileRadius
                opacity: parent.hot
            }

            ZoneLabel {
                glyph: ""
                label: I18n.tr("Tray")
            }

            DropArea {
                id: trayDrop
                anchors.fill: parent
                keys: ["text/uri-list"]
                onDropped: drop => {
                    const paths = root.stash.pathsFromUrls(drop.urls);
                    drop.accept();
                    root.toTray(paths);
                }
            }
        }

        // ── LocalSend zone: always tinted, hover bumps the alpha ──
        Item {
            visible: root.cfg.localsend
            width: root.cfg.dropZoneWidth
            height: root.cfg.dropZoneHeight

            property real hot: sendDrop.containsDrag ? 1 : 0
            Behavior on hot { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }

            Rectangle {
                anchors.fill: parent
                radius: root.tileRadius
                color: Qt.alpha(root.theme.cardBlue, 0.18 + 0.16 * parent.hot)
            }

            ZoneLabel {
                glyph: ""
                label: "LocalSend"
            }

            DropArea {
                id: sendDrop
                anchors.fill: parent
                keys: ["text/uri-list"]
                onDropped: drop => {
                    const paths = root.stash.pathsFromUrls(drop.urls);
                    drop.accept();
                    if (paths.length > 0)
                        root.toSend(paths);
                    else
                        root.closeRequested();
                }
            }
        }
    }

    // Icon over label, left-aligned and vertically centred (pShell layout).
    component ZoneLabel: Column {
        property string glyph
        property string label
        anchors.left: parent.left
        anchors.leftMargin: root.cfg.padding
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Text {
            text: parent.glyph
            color: root.theme.cardBlue
            font.family: root.theme.iconFamily
            font.pixelSize: 28
        }
        Text {
            text: parent.label
            color: root.theme.islandFg
            font.pixelSize: 13
        }
    }
}
