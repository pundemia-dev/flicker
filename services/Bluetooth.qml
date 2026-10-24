import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import "../config"

QtObject {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    // Quickshell's adapter flag is `enabled` (there is no `powered`: the card
    // read Off forever and its toggle did nothing).
    readonly property bool powered: adapter?.enabled ?? false
    readonly property var connectedDevices: adapter ? adapter.devices.values.filter(d => d.state === BluetoothDeviceState.Connected) : []

    // The switch's last state (card / panel) persists in
    // statePath("bluetooth.json") (`saved`: true / false / null = never
    // tapped) and is re-applied once the adapter shows up, when Airplane sets
    // `pending` (once per login): BlueZ AutoEnable powers it on at every boot
    // otherwise. Only taps here are saved.
    property var saved: null
    property bool pending: false

    function toggle(): void {
        if (!adapter)
            return;
        adapter.enabled = !adapter.enabled;
        root.saved = adapter.enabled;
        root.pending = false;
        stateFile.setText(JSON.stringify({ version: 1, bt: root.saved }));
    }

    // BlueZ may still power the adapter right after it appears; settle first.
    property Timer restore: Timer {
        interval: 1500
        running: !!root.adapter && root.pending && root.saved !== null && (Config.data.persist?.bluetooth ?? true)
        onTriggered: {
            root.pending = false;
            if (root.adapter && root.adapter.enabled !== root.saved)
                root.adapter.enabled = root.saved;
        }
    }

    // bluetooth.autoOffMin: powered, nothing connected and no scan (the
    // panel discovers while open) for that long = adapter off. Not saved:
    // the next boot still follows the last tap.
    readonly property int autoOffMin: Config.data.bluetooth?.autoOffMin ?? 0
    property Timer autoOff: Timer {
        interval: Math.max(1, root.autoOffMin) * 60000
        running: root.autoOffMin > 0 && root.powered && root.connectedDevices.length === 0 && !(root.adapter?.discovering ?? false)
        onTriggered: {
            console.info("[bluetooth] nothing connected for", root.autoOffMin, "min, powering off");
            if (root.adapter)
                root.adapter.enabled = false;
        }
    }

    property FileView stateFile: FileView {
        path: Quickshell.statePath("bluetooth.json")
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(stateFile.text());
                if (typeof s.bt === "boolean")
                    root.saved = s.bt;
            } catch (e) {
                console.warn("Bluetooth: bad state file, ignoring:", e);
            }
        }
    }
}
