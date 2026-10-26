import QtQuick
import "../config"

// Caffeine mode: keeps the session awake (no idle dim / lock / screen off /
// sleep). services/Idle reads `active` directly (an inhibitor on our own
// surface would stop counting while it is hidden or occluded); every Island
// also holds an `IdleInhibitor` bound to it, for idle daemons outside the
// shell. Optionally timed (`until`, Amphetamine-style: "for 1 h"), and off by
// itself on battery at `caffeine.offBelowPercent`. The state survives a
// restart / reboot (statePath("caffeine.json"), restored without an event; a
// timer that ran out meanwhile stays off). Toggling posts an event: the cup
// fills (on) / drains (off) — CoffeeGlyph.
QtObject {
    id: root
    required property var events
    property var battery: null

    property bool active: false
    // Epoch ms the mode ends at; 0 = until turned off.
    property real until: 0
    // Ticks while timed, so `left` / `status` stay live.
    property real now: Date.now()
    readonly property int left: root.active && root.until > 0 ? Math.max(0, Math.round((root.until - root.now) / 1000)) : 0

    readonly property string status: {
        if (!root.active)
            return I18n.tr("Off");
        if (root.until <= 0)
            return I18n.tr("On");
        const m = Math.ceil(root.left / 60);
        return m >= 60 ? I18n.tr("%1 h %2 min left").arg(Math.floor(m / 60)).arg(m % 60) : I18n.tr("%1 min left").arg(m);
    }

    function toggle(): void {
        root.setActive(!root.active, Config.data.caffeine?.minutes ?? 0);
    }
    // minutes: 0 = until turned off. Again with a new duration while on
    // re-times it (event too).
    function setActive(on: bool, minutes: real): void {
        const until = on && minutes > 0 ? Date.now() + minutes * 60000 : 0;
        if (on === root.active && until === 0 && root.until === 0)
            return;
        root.active = on;
        root.until = until;
        root.now = Date.now();
        stateFile.write({ active: on, until: until });
        root.events.cancel(on ? "caffeine:off" : "caffeine:on");
        if (!(Config.data.events.caffeine ?? true))
            return;
        root.events.post({
            key: on ? "caffeine:on" : "caffeine:off",
            glyph: "coffee",
            glyphArgs: { drain: !on },
            icon: "\uef0e", // tabler coffee (font fallback)
            color: "coffee",
            text: !on ? I18n.tr("Off") : minutes <= 0 ? I18n.tr("On")
                : minutes >= 60 && minutes % 60 === 0 ? I18n.tr("%1 h").arg(minutes / 60) : I18n.tr("%1 min").arg(Math.round(minutes))
        });
    }

    readonly property bool batteryLow: {
        const b = root.battery;
        const min = Config.data.caffeine?.offBelowPercent ?? 10;
        return !!b && b.present && !b.charging && min > 0 && b.percent <= min;
    }
    onBatteryLowChanged: if (root.batteryLow && root.active) {
        console.log("[caffeine] off: battery at", root.battery.percent, "%");
        root.setActive(false, 0);
    }

    property Timer tick: Timer {
        running: root.active && root.until > 0
        repeat: true
        triggeredOnStart: true
        interval: 15000
        onTriggered: {
            root.now = Date.now();
            if (root.now >= root.until)
                root.setActive(false, 0);
        }
    }

    property StateFile stateFile: StateFile {
        name: "caffeine.json"
        onLoaded: {
            if (!(Config.data.persist?.caffeine ?? true))
                return;
            const s = stateFile.read();
            const until = typeof s.until === "number" ? s.until : 0;
            root.active = s.active === true && (until === 0 || until > Date.now());
            root.until = root.active ? until : 0;
        }
    }
}
