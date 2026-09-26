import QtQuick
import Quickshell.Bluetooth

QtObject {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool powered: adapter?.powered ?? false
    readonly property var connectedDevices: adapter ? adapter.devices.values.filter(d => d.state === BluetoothDeviceState.Connected) : []

    function toggle(): void {
        if (adapter)
            adapter.powered = !adapter.powered;
    }
}
