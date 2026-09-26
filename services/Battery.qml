import QtQuick
import Quickshell.Services.UPower
import "../config"

QtObject {
    id: root

    readonly property var batteries: UPower.devices.values.filter(d => d.isPresent && d.isLaptopBattery)
    readonly property var battery: batteries[0] ?? null

    readonly property bool present: battery !== null
    readonly property int percent: battery ? Math.round(battery.percentage * 100) : 0
    readonly property bool charging: battery ? battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.FullyCharged : false
    readonly property bool low: present && !charging && percent <= Config.data.battery.lowPercent
    readonly property int secondsToEmpty: battery?.timeToEmpty ?? 0
    readonly property int secondsToFull: battery?.timeToFull ?? 0
}
