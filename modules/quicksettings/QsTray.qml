pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../../components"

// System tray (StatusNotifierItem) in the rail column, under the tab icons
// (QsTabRail.belowTop), one icon per item top to bottom. Left click =
// activate (an item that is only a menu opens it) and the module closes so
// the app's window shows; right click or a long press (cfg.holdMs) = the
// item's menu, middle = secondary activate. The menu is a QS panel
// (panels/TrayMenuPanel via menuRequested → the module's expander), not the
// platform popup: QsMenuAnchor needs QApplication mode. The wheel is left to
// the module (it flips tabs).
Column {
    id: root
    required property var cfg
    required property var theme
    property var frost: null
    signal activated
    // src = the icon slot; payload = { item, icon }; h = panel height.
    signal menuRequested(Item src, var payload, real h)

    spacing: root.cfg.railSpacing

    // "name?path=dir" (apps shipping their own icons): the themed icon if
    // there is one, else the file in that dir.
    function iconOf(icon: string): string {
        if (!icon.includes("?path="))
            return icon;
        const [name, path] = icon.split("?path=");
        const file = name.slice(name.lastIndexOf("/") + 1);
        return Quickshell.iconPath(file, true) || Qt.resolvedUrl(`${path}/${file}`);
    }

    // Panel height for a menu's top level (rows as TrayMenuPanel lays them
    // out), at most expand.panels.tray.height.
    function menuHeight(entries: var): real {
        const pc = root.cfg.listPanel ?? {};
        let h = (pc.headerHeight ?? 54) + 1 + 4 + 8;
        for (const e of entries)
            h += e.isSeparator ? 9 : (pc.rowHeight ?? 42);
        return Math.min(h, root.cfg.expand?.panels?.tray?.height ?? 420);
    }

    // Debug IPC (QuickSettingsModule.expandCard "tray<i>").
    function openMenuAt(i: int): void {
        trayRepeater.itemAt(i)?.openMenu();
    }

    Repeater {
        id: trayRepeater
        model: SystemTray.items
        delegate: Item {
            id: slot
            required property SystemTrayItem modelData
            width: root.cfg.trayIcon
            height: root.cfg.trayIcon
            scale: ma.pressed ? 0.9 : 1
            Behavior on scale { Spring { stiffness: 6; damp: 0.45; eps: 0.002 } }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: root.frost?.layerColor(root.theme?.qsDisc ?? "#3A3A3C") ?? (root.theme?.qsDisc ?? "#3A3A3C")
                opacity: ma.containsMouse ? 1 : 0
                Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
            }

            IconImage {
                anchors.centerIn: parent
                implicitSize: root.cfg.trayIconSize
                source: root.iconOf(slot.modelData.icon)
                asynchronous: true
            }

            // Keeps the menu fetched: its size is known when it opens.
            QsMenuOpener {
                id: opener
                menu: slot.modelData.menu
            }
            function openMenu(): void {
                root.menuRequested(slot, {
                    item: slot.modelData,
                    icon: root.iconOf(slot.modelData.icon)
                }, root.menuHeight(opener.children.values));
            }

            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                pressAndHoldInterval: root.cfg.holdMs ?? 450
                // A handled hold swallows the release's click.
                onPressAndHold: e => {
                    if (e.button === Qt.LeftButton && slot.modelData.hasMenu)
                        slot.openMenu();
                }
                onClicked: e => {
                    const item = slot.modelData;
                    if (e.button === Qt.MiddleButton)
                        item.secondaryActivate();
                    else if (item.hasMenu && (e.button === Qt.RightButton || item.onlyMenu))
                        slot.openMenu();
                    else if (e.button === Qt.RightButton)
                        item.secondaryActivate();
                    else {
                        item.activate();
                        root.activated();
                    }
                }
            }
        }
    }
}
