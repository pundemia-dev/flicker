import QtQuick
import "../../../components"
import "../../../config"
import "PanelSync.js" as PanelSync

// Expanded Bluetooth card (DropExpand panel): header disc toggles the
// adapter; below, paired devices (connected first, then by name) and, while
// the panel is open (adapter discovery runs), named nearby ones. A tap
// connects / disconnects a paired device, pairs + trusts + connects a new
// one. Rows look their device up by address (live state, no copies).
Item {
    id: root
    property var services: null
    property var cfg: null
    property var theme: null
    property var frost: null
    property var expander: null

    readonly property var bt: root.services?.bluetooth ?? null
    readonly property var adapter: root.bt?.adapter ?? null
    readonly property var pc: root.cfg?.listPanel ?? ({})
    readonly property real pad: root.pc.padding ?? 18
    readonly property bool on: root.bt?.powered ?? false
    readonly property var devices: root.adapter?.devices?.values ?? []

    // Discovery only while the panel exists (and the adapter is on).
    function discover(want: bool): void {
        if (root.adapter && root.adapter.enabled && root.adapter.discovering !== want)
            root.adapter.discovering = want;
    }
    Component.onCompleted: root.discover(true)
    onOnChanged: root.discover(root.on)
    Component.onDestruction: root.discover(false)

    function deviceOf(address: string): var {
        return root.devices.find(d => d.address === address) ?? null;
    }

    // Unnamed devices (BlueZ alias = the address) are noise in the list.
    readonly property var sorted: {
        if (!root.on)
            return [];
        const named = root.devices.filter(d => d.paired || (d.deviceName ?? "") !== "");
        return named.map(d => ({ address: d.address, rank: d.connected ? 0 : d.paired ? 1 : 2, name: d.name ?? "" }))
            .sort((a, b) => (a.rank - b.rank) || a.name.localeCompare(b.name));
    }
    onSortedChanged: PanelSync.sync(rows, root.sorted, "address")
    ListModel {
        id: rows
    }

    PanelHeader {
        id: header
        width: parent.width
        pc: root.pc
        theme: root.theme
        frost: root.frost
        pad: root.pad
        on: root.on
        glyph: root.on ? "" : ""
        title: "Bluetooth"
        status: {
            if (!root.on)
                return I18n.tr("Off");
            const c = root.bt?.connectedDevices ?? [];
            return c.length > 0 ? c.map(d => d.name).join(", ") : I18n.tr("On");
        }
        onToggled: root.bt?.toggle()
    }

    ListView {
        id: list
        y: header.height + 4
        width: parent.width
        height: parent.height - y - 8
        clip: true
        model: rows
        boundsBehavior: Flickable.StopAtBounds
        delegate: BluetoothRow {
            required property var model
            width: list.width
            panel: root
            device: root.deviceOf(model.address)
        }
    }

    Text {
        anchors.centerIn: list
        visible: rows.count === 0
        text: !root.on ? I18n.tr("Bluetooth is off") : I18n.tr("Searching…")
        color: root.theme?.cardDim ?? "#99EBEBF5"
        font.pixelSize: root.pc.textSize ?? 14
    }
}
