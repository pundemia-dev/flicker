import QtQuick
import Quickshell.Services.UPower
import "../config"

// Event source: the charger. Plugged in -> bolt (green) + the percentage,
// then the time to full rolls in (`texts` steps, events.textStepMs).
// Pulled -> bolt-off (orange) + the percentage, then the time to empty.
// Both live; a step stays on the percentage while UPower has no estimate
// yet. Each one cancels the other if it is still shown or queued.
QtObject {
    id: root
    required property var events
    required property var battery

    readonly property bool plugged: !UPower.onBattery
    // Start-up state is no event (UPower answers asynchronously).
    property bool armed: false
    property Timer arm: Timer {
        running: true
        interval: Config.data.events.startupQuietMs
        onTriggered: root.armed = true
    }

    onPluggedChanged: {
        if (!root.armed || !root.battery.present)
            return;
        root.events.cancel(root.plugged ? "discharging" : "charging");
        if (!(Config.data.events.charging ?? true))
            return;
        const percent = () => `${root.battery.percent}%`;
        root.events.post(root.plugged ? {
            key: "charging",
            icon: "", // bolt
            color: "batteryGood",
            texts: [percent, () => root.duration(root.battery.secondsToFull)]
        } : {
            key: "discharging",
            icon: "", // bolt-off
            color: "accentOrange",
            texts: [percent, () => root.duration(root.battery.secondsToEmpty)]
        });
    }

    function duration(s: int): string {
        if (s <= 0)
            return `${root.battery.percent}%`;
        const total = Math.max(1, Math.round(s / 60));
        const h = Math.floor(total / 60);
        const m = total % 60;
        if (h === 0)
            return I18n.tr("%1 min").arg(m);
        return m === 0 ? I18n.tr("%1 h").arg(h) : I18n.tr("%1 h %2 min").arg(h).arg(m);
    }
}
