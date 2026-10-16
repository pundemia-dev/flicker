import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../config"

// Event source: battery milestones (BatteryGlyph).
//   full      on the charger and UPower says FullyCharged, or the level
//             reached the charge limit (`battery.chargeLimit`, 0 = read
//             /sys/class/power_supply/<bat>/charge_control_end_threshold,
//             100 when the driver has none). Once per charge: re-armed by
//             unplugging or by dropping `fullRearm` % below the limit.
//   critical  discharging at / below `battery.criticalPercent`: a blinking
//             red sliver + the time left. Once per discharge (re-armed by
//             charging or by climbing back over the threshold).
// Startup state is no event (`events.startupQuietMs`).
Scope {
    id: root
    required property var events
    required property var battery
    required property var charging

    readonly property var cfg: Config.data.battery
    property int sysLimit: 100
    readonly property int limit: (root.cfg.chargeLimit ?? 0) > 0 ? root.cfg.chargeLimit : root.sysLimit
    readonly property bool plugged: !UPower.onBattery
    readonly property bool isFull: root.battery.present && root.plugged
        && (root.battery.battery?.state === UPowerDeviceState.FullyCharged || root.battery.percent >= root.limit)
    readonly property bool isCritical: root.battery.present && !root.plugged
        && root.battery.percent > 0 && root.battery.percent <= (root.cfg.criticalPercent ?? 5)

    property bool fullDone: false
    property bool criticalDone: false
    property bool armed: false
    Timer {
        running: true
        interval: Config.data.events.startupQuietMs
        onTriggered: {
            // Already full / critical at start: not news.
            root.fullDone = root.isFull;
            root.criticalDone = root.isCritical;
            root.armed = true;
        }
    }

    Process {
        running: true
        command: ["sh", "-c", "cat /sys/class/power_supply/BAT*/charge_control_end_threshold 2>/dev/null | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseInt(this.text);
                if (v > 0 && v <= 100)
                    root.sysLimit = v;
            }
        }
    }

    onIsFullChanged: root.check()
    onIsCriticalChanged: root.check()
    onPluggedChanged: {
        if (!root.plugged)
            root.fullDone = false;
        else
            root.criticalDone = false;
        root.events.cancel(root.plugged ? "battery:critical" : "battery:full");
    }
    readonly property int percent: root.battery.percent
    onPercentChanged: {
        if (root.percent < root.limit - (root.cfg.fullRearm ?? 3))
            root.fullDone = false;
        if (root.percent > (root.cfg.criticalPercent ?? 5) + 2)
            root.criticalDone = false;
    }

    function check(): void {
        if (!root.armed)
            return;
        if (root.isFull && !root.fullDone) {
            root.fullDone = true;
            if (Config.data.events.batteryFull ?? true)
                root.announceFull();
        }
        if (root.isCritical && !root.criticalDone) {
            root.criticalDone = true;
            if (Config.data.events.batteryCritical ?? true)
                root.announceCritical();
        }
    }

    // Also IPC `island eventDemo full|critical`.
    function announceFull(): void {
        root.events.post({
            key: "battery:full",
            glyph: "battery",
            glyphArgs: { level: root.limit / 100 },
            icon: "",
            color: "batteryGood",
            texts: [root.limit >= 100 ? I18n.tr("Charged") : I18n.tr("Charged to limit"), () => `${root.battery.percent}%`]
        });
    }
    function announceCritical(): void {
        root.events.post({
            key: "battery:critical",
            glyph: "battery",
            glyphArgs: { level: root.battery.percent / 100, critical: true },
            icon: "",
            color: "batteryLow",
            texts: [() => `${root.battery.percent}%`, () => root.charging.duration(root.battery.secondsToEmpty)]
        });
    }
}
