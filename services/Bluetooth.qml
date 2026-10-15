import QtQuick
import Quickshell.Bluetooth

QtObject {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    // Quickshell's adapter flag is `enabled` (there is no `powered`: the card
    // read Off forever and its toggle did nothing).
    readonly property bool powered: adapter?.enabled ?? false
    readonly property var connectedDevices: adapter ? adapter.devices.values.filter(d => d.state === BluetoothDeviceState.Connected) : []

    function toggle(): void {
        if (adapter)
            adapter.enabled = !adapter.enabled;
    }
}
