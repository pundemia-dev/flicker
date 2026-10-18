import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Airplane Mode (QS card `airplane`, IPC `island airplane`): every radio
// soft-blocked through rfkill (/dev/rfkill is user-writable — no root).
// `active` follows the live rfkill state (`rfkill event`), so a block made
// elsewhere (Fn key, `rfkill block all`) shows here too.
// Turning it off restores what was on before (iOS): only the radio types
// that were unblocked get unblocked, and the Bluetooth adapter goes back
// to its own power state (BlueZ powers it on after an unblock otherwise).
// That snapshot persists in statePath("airplane.json"); without one (the
// block came from elsewhere) "off" unblocks everything.
// quicksettings.airplane.dnd: Do Not Disturb follows the mode — switched on
// with it, and off again with it only if it was the mode that switched it on.
// No rfkill devices (`available` false) → the card reads "Unavailable".
Scope {
    id: root
    required property var events
    required property var bluetooth
    required property var notifications

    readonly property var cfg: Config.data.quicksettings.airplane ?? ({})
    // idx -> { type, soft, hard } (rfkill event: type 1 wlan, 2 bluetooth…).
    property var devices: ({})
    readonly property var list: Object.values(root.devices)
    readonly property bool available: root.list.length > 0
    readonly property bool active: root.available && root.list.every(d => d.soft || d.hard)
    // { types: [rfkill type names unblocked before], bt: adapter powered, dnd: we set DND }
    property var before: null

    readonly property var typeNames: ["all", "wlan", "bluetooth", "uwb", "wimax", "wwan", "gps", "fm", "nfc"]

    function toggle(): void {
        root.setActive(!root.active);
    }
    function setActive(on: bool): void {
        if (!root.available || on === root.active)
            return;
        if (on) {
            const types = [...new Set(root.list.filter(d => !d.soft && !d.hard).map(d => root.typeNames[d.type] ?? "all"))];
            root.save({ types, bt: root.bluetooth?.powered ?? false, dnd: false });
            Quickshell.execDetached(["rfkill", "block", "all"]);
        } else {
            const types = root.before?.types ?? [];
            Quickshell.execDetached(["rfkill", "unblock", ...(types.length > 0 && !types.includes("all") ? types : ["all"])]);
            if (root.before && types.includes("bluetooth"))
                btRestore.restart();
        }
    }

    function save(state: var): void {
        root.before = state;
        stateFile.setText(JSON.stringify(Object.assign({ version: 1 }, state)));
    }

    // The adapter reports its power only once BlueZ has seen the unblock.
    Timer {
        id: btRestore
        interval: 1500
        onTriggered: {
            const adapter = root.bluetooth?.adapter;
            if (adapter && root.before && adapter.enabled !== root.before.bt)
                adapter.enabled = root.before.bt;
        }
    }

    onActiveChanged: {
        if (!arm.armed)
            return;
        if (root.active) {
            if ((root.cfg.dnd ?? false) && root.notifications && !root.notifications.doNotDisturb) {
                root.notifications.doNotDisturb = true;
                root.save(Object.assign({}, root.before ?? {}, { dnd: true }));
            }
        } else if (root.before?.dnd) {
            if (root.notifications)
                root.notifications.doNotDisturb = false;
            root.save(Object.assign({}, root.before, { dnd: false }));
        }
        root.events.cancel(root.active ? "airplane:off" : "airplane:on");
        if (!(Config.data.events.airplane ?? true))
            return;
        root.events.post({
            key: root.active ? "airplane:on" : "airplane:off",
            icon: "", // tabler plane
            color: "qsOrange",
            text: root.active ? I18n.tr("Airplane Mode") : I18n.tr("Off")
        });
    }

    // The start-up state is not a change.
    Timer {
        id: arm
        property bool armed: false
        running: true
        interval: Config.data.events.startupQuietMs
        onTriggered: armed = true
    }

    // Lists every device on start, then one line per change. stdbuf: rfkill
    // block-buffers stdout into a pipe.
    Process {
        id: watch
        running: true
        command: ["stdbuf", "-oL", "rfkill", "event"]
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/idx (\d+) type (\d+) op (\d+) soft (\d+) hard (\d+)/);
                if (!m)
                    return;
                const next = Object.assign({}, root.devices);
                if (m[3] === "1")
                    delete next[m[1]];
                else
                    next[m[1]] = { type: +m[2], soft: m[4] === "1", hard: m[5] === "1" };
                root.devices = next;
            }
        }
        onExited: code => {
            console.info("[airplane] rfkill event exited:", code);
            root.devices = {};
            if (code === 0 || retries.count++ < 5)
                retries.restart();
        }
    }
    Timer {
        id: retries
        property int count: 0
        interval: 5000
        onTriggered: watch.running = true
    }

    FileView {
        id: stateFile
        path: Quickshell.statePath("airplane.json")
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(stateFile.text());
                root.before = { types: s.types ?? [], bt: s.bt ?? true, dnd: s.dnd ?? false };
            } catch (e) {
                console.warn("Airplane: bad state file, ignoring:", e);
            }
        }
    }
}
