pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../../components"

// System tray (StatusNotifierItem) in the rail column, under the tab icons
// (QsTabRail.belowTop), one icon per item top to bottom. Left click =
// activate (an item that is only a menu opens it) and the module closes so
// the app's window shows; right click = the item's menu, middle = secondary
// activate. Menus are the platform popup (QsMenuAnchor) beside the icon.
// The wheel is left to the module (it flips tabs).
Column {
    id: root
    required property var cfg
    required property var theme
    property var frost: null
    signal activated

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

    Repeater {
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
                opacity: ma.containsMouse || menu.visible ? 1 : 0
                Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
            }

            IconImage {
                anchors.centerIn: parent
                implicitSize: root.cfg.trayIconSize
                source: root.iconOf(slot.modelData.icon)
                asynchronous: true
            }

            QsMenuAnchor {
                id: menu
                menu: slot.modelData.menu
                anchor.item: slot
                anchor.edges: Edges.Bottom | Edges.Right
                anchor.gravity: Edges.Bottom | Edges.Right
            }

            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: e => {
                    const item = slot.modelData;
                    if (e.button === Qt.MiddleButton)
                        item.secondaryActivate();
                    else if (item.hasMenu && (e.button === Qt.RightButton || item.onlyMenu))
                        menu.open();
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
