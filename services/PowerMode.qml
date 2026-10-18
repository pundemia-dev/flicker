import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../config"

// Low Power Mode (QS card `lowPower`, IPC `island powerSave`): the system
// power profile through the standard D-Bus API
// (org.freedesktop.UPower.PowerProfiles) — power-profiles-daemon, tlp-pd and
// tuned-ppd all serve it, so the daemon decides what "power-saver" means on
// each machine (TLP: its *_ON_SAV settings). `active` follows the live
// profile: a change made elsewhere (powerprofilesctl, TLP resetting it on a
// power-source change) shows here too.
// While active the shell sheds its own background work (Config.powerSave):
// no thumbnail warm-up / semantic indexing at all, and every service that
// starts heavy work on its own checks `active`. What the user starts by hand
// (a forced index, a transcription, a search) still runs.
// No daemon (`available` false, probed at start and on every tap) → the card
// reads "Unavailable" and nothing is written.
QtObject {
    id: root
    required property var events

    property bool available: false
    readonly property bool active: root.available && PowerProfiles.profile === PowerProfile.PowerSaver
    // The profile before we switched to power-saver: restored on "off".
    property int before: PowerProfile.Balanced

    function toggle(): void {
        root.setActive(!root.active);
    }
    function setActive(on: bool): void {
        if (!root.available) {
            probe.running = true;
            return;
        }
        if (on === root.active)
            return;
        if (on) {
            root.before = PowerProfiles.profile;
            PowerProfiles.profile = PowerProfile.PowerSaver;
        } else {
            PowerProfiles.profile = root.before === PowerProfile.PowerSaver ? PowerProfile.Balanced : root.before;
        }
    }

    onActiveChanged: {
        root.events.cancel(root.active ? "powersave:off" : "powersave:on");
        if (!(Config.data.events.powerSave ?? true))
            return;
        root.events.post({
            key: root.active ? "powersave:on" : "powersave:off",
            icon: "", // tabler battery-eco
            color: "qsYellow",
            text: root.active ? I18n.tr("Low Power") : I18n.tr("Off")
        });
    }

    // Running owner or D-Bus activatable (power-profiles-daemon starts on
    // the first call).
    property Process probe: Process {
        running: true
        command: ["sh", "-c", "for m in ListNames ListActivatableNames; do"
            + " dbus-send --system --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.$m 2>/dev/null"
            + " | grep -q '\"org.freedesktop.UPower.PowerProfiles\"' && exit 0; done; exit 1"]
        onExited: code => {
            root.available = code === 0;
            if (!root.available)
                console.info("[powermode] no power-profiles daemon (power-profiles-daemon / tlp-pd / tuned-ppd)");
        }
    }
}
