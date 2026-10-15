import QtQuick
import "../../../components"
import "../../../config"
import "PanelSync.js" as PanelSync

// Expanded Wi‑Fi card (QsExpander panel): header = the card's glyph disc
// (tap toggles Wi‑Fi) + title + current network; below, the networks
// (services/Network list, refreshed while this panel exists). A tap joins
// a saved / open network; a new secured one opens a password field in its
// row (the island takes the keyboard meanwhile, `wantsKeyboard`).
// Services come from the factory's Component, `expander` from DropExpand.
Item {
    id: root
    property var services: null
    property var cfg: null
    property var theme: null
    property var frost: null
    property var expander: null

    readonly property var net: root.services?.network ?? null
    readonly property var pc: root.cfg?.listPanel ?? ({})
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
    // ListModel synced in place (PanelSync).
    onSortedChanged: {
        PanelSync.sync(rows, root.sorted, "ssid");
        if (root.joinSsid && !root.sorted.some(n => n.ssid === root.joinSsid))
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

    PanelHeader {
        id: header
        width: parent.width
        pc: root.pc
        theme: root.theme
        frost: root.frost
        pad: root.pad
        on: root.on
        glyph: root.on ? "\ueb52" : "\uecfa"
        title: "Wi‑Fi"
        status: !root.on ? I18n.tr("Off") : (root.net?.wifiConnected ? root.net.wifiSsid : I18n.tr("Not connected"))
        onToggled: root.net?.toggleWifi()
    }

    // Networks -------------------------------------------------------------
    ListView {
        id: list
        y: header.height + 4
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
