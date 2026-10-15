import QtQuick
import "../../../components"
import "../../../config"

// Expanded Wi‑Fi card (QsExpander panel): header = the card's glyph disc
// (tap toggles Wi‑Fi) + title + current network; below, the networks
// (services/Network list, refreshed while this panel exists). A tap joins
// a saved / open network; a new secured one opens a password field in its
// row (the island takes the keyboard meanwhile, `wantsKeyboard`).
// Properties are set by the expander's Loader (onLoaded): null-safe reads.
Item {
    id: root
    property var services: null
    property var cfg: null
    property var theme: null
    property var frost: null
    property var expander: null

    readonly property var net: root.services?.network ?? null
    readonly property var pc: root.cfg?.wifiPanel ?? ({})
    readonly property real pad: root.pc.padding ?? 18
    readonly property bool on: root.net?.wifiEnabled ?? false
    // Row with the password field open ("" = none).
    property string joinSsid: ""
    readonly property bool wantsKeyboard: root.joinSsid !== ""

    onNetChanged: root.net?.setScanning(true)
    Component.onDestruction: root.net?.setScanning(false)

    // Stable order: current, saved (by name), others by signal bars then
    // name — a raw signal sort reshuffled rows on every scan.
    function bars(s: int): int {
        return s >= 70 ? 3 : s >= 45 ? 2 : s >= 20 ? 1 : 0;
    }
    readonly property var sorted: {
        if (!root.on)
            return [];
        return (root.net?.networks ?? []).slice().sort((a, b) => (b.active - a.active) || (b.known - a.known)
            || (a.known ? 0 : root.bars(b.signal) - root.bars(a.signal)) || a.ssid.localeCompare(b.ssid));
    }
    // ListModel synced in place (a reassigned array rebuilt every row and
    // reset the scroll on each scan).
    onSortedChanged: {
        const list = root.sorted;
        for (let i = rows.count - 1; i >= 0; i--)
            if (!list.some(n => n.ssid === rows.get(i).ssid))
                rows.remove(i);
        list.forEach((n, i) => {
            let j = -1;
            for (let k = i; k < rows.count; k++)
                if (rows.get(k).ssid === n.ssid) {
                    j = k;
                    break;
                }
            if (j < 0)
                rows.insert(i, n);
            else {
                if (j !== i)
                    rows.move(j, i, 1);
                rows.set(i, n);
            }
        });
        if (root.joinSsid && !list.some(n => n.ssid === root.joinSsid))
            root.joinSsid = "";
    }
    ListModel {
        id: rows
    }

    // A failed join of a new secured network: ask for the password again.
    Connections {
        target: root.net
        function onFailedChanged(): void {
            const n = root.net.networks.find(x => x.ssid === root.net.failed);
            if (n?.secure && !n.known)
                root.joinSsid = n.ssid;
        }
    }

    function tap(n: var): void {
        if (n.active || root.net?.connecting)
            return;
        if (n.secure && !n.known) {
            root.joinSsid = root.joinSsid === n.ssid ? "" : n.ssid;
            return;
        }
        root.joinSsid = "";
        root.net?.join(n.ssid, "");
    }

    // Header ---------------------------------------------------------------
    Item {
        id: header
        width: parent.width
        height: root.pc.headerHeight ?? 54

        Rectangle {
            id: disc
            readonly property real d: Math.round(header.height * 0.67)
            x: root.pad
            y: Math.round((header.height - height) / 2)
            width: d
            height: d
            radius: d / 2
            color: discColor.value
            scale: discMa.pressed ? 0.9 : 1
            Behavior on scale { Spring { stiffness: 6; damp: 0.45; eps: 0.002 } }
            SpringColor {
                id: discColor
                target: root.on ? (root.theme?.qsBlue ?? "#017EFC") : (root.frost?.layerColor(root.theme?.qsDisc ?? "#3A3A3C") ?? (root.theme?.qsDisc ?? "#3A3A3C"))
                stiffness: 5
                damping: 0.6
            }
            Icon {
                anchors.centerIn: parent
                text: root.on ? "" : ""
                font.family: root.theme?.iconFamily ?? "tabler-icons"
                iconSize: root.pc.glyphSize ?? 20
                iconColor: "white"
            }
            MouseArea {
                id: discMa
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: root.net?.toggleWifi()
            }
        }

        Column {
            x: disc.x + disc.width + 12
            width: header.width - x - root.pad
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
                width: parent.width
                text: "Wi‑Fi"
                color: "white"
                font.pixelSize: root.pc.titleSize ?? 17
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                text: !root.on ? I18n.tr("Off") : (root.net?.wifiConnected ? root.net.wifiSsid : I18n.tr("Not connected"))
                color: root.theme?.cardDim ?? "#99EBEBF5"
                font.pixelSize: (root.pc.textSize ?? 14) - 2
                elide: Text.ElideRight
            }
        }
    }

    Rectangle {
        id: divider
        y: header.height
        x: root.pad
        width: parent.width - 2 * root.pad
        height: 1
        color: root.theme?.launcherDivider ?? "#2EFFFFFF"
    }

    // Networks -------------------------------------------------------------
    ListView {
        id: list
        y: divider.y + divider.height + 4
        width: parent.width
        height: parent.height - y - 8
        clip: true
        model: rows
        boundsBehavior: Flickable.StopAtBounds
        delegate: WifiRow {
            required property var model
            width: list.width
            panel: root
            ssid: model.ssid
            strength: model.signal
            secure: model.secure
            active: model.active
            known: model.known
        }
    }

    Text {
        anchors.centerIn: list
        visible: rows.count === 0
        text: !root.on ? I18n.tr("Wi‑Fi is off") : I18n.tr("Searching…")
        color: root.theme?.cardDim ?? "#99EBEBF5"
        font.pixelSize: root.pc.textSize ?? 14
    }
}
