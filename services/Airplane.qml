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
// That snapshot persists in statePath("airplane.json") and is dropped once
// the mode is off; without one (the block came from elsewhere) "off"
// unblocks everything and the radios follow their own last switch state
// (Network `savedRadio` / Bluetooth `saved`). Wi‑Fi is switched back on in NM after ANY
// exit (Fn key, rfkill elsewhere too): an rfkill unblock alone may leave
// NM's radio off.
// The mode itself survives a reboot (rfkill state does not:
// systemd-rfkill is masked here): `on` in the same file, re-blocked on
// start before Network / Bluetooth re-apply their switches (they don't
// then). `on` is written only while rfkill devices exist (they vanish at
// shutdown = no "off"). That start-up restore runs once per login
// (marker in $XDG_RUNTIME_DIR): a hot reload would undo nmcli / bluetoothctl
// changes made since.
// quicksettings.airplane.dnd: Do Not Disturb follows the mode — switched on
// with it, and off again with it only if it was the mode that switched it on.
// No rfkill devices (`available` false) → the card reads "Unavailable".
Scope {
    id: root
    required property var events
    required property var bluetooth
    required property var network
    required property var notifications

    readonly property var cfg: Config.data.quicksettings.airplane ?? ({})
    // idx -> { type, soft, hard } (rfkill event: type 1 wlan, 2 bluetooth…).
    property var devices: ({})
    readonly property var list: Object.values(root.devices)
    readonly property bool available: root.list.length > 0
    readonly property bool active: root.available && root.list.every(d => d.soft || d.hard)
    // { types: [rfkill type names unblocked before], wifi: NM radio on,
    //   bt: adapter powered, dnd: we set DND }
    property var before: null
    // Airplane Mode was on when last seen (persisted).
    property bool savedOn: false

    readonly property var typeNames: ["all", "wlan", "bluetooth", "uwb", "wimax", "wwan", "gps", "fm", "nfc"]

    function toggle(): void {
        root.setActive(!root.active);
    }
    function setActive(on: bool): void {
        if (!root.available || on === root.active)
            return;
        if (on) {
            const types = [...new Set(root.list.filter(d => !d.soft && !d.hard).map(d => root.typeNames[d.type] ?? "all"))];
            root.save({ types, wifi: root.network?.wifiEnabled ?? true, bt: root.bluetooth?.powered ?? false, dnd: false });
            Quickshell.execDetached(["rfkill", "block", "all"]);
        } else {
            const types = root.before?.types ?? [];
            Quickshell.execDetached(["rfkill", "unblock", ...(types.length > 0 && !types.includes("all") ? types : ["all"])]);
        }
    }

    function save(state: var): void {
        root.before = state;
        root.write();
    }
    function write(): void {
        stateFile.setText(JSON.stringify(Object.assign({ version: 1, on: root.savedOn }, root.before ?? {})));
    }

    // After an exit: what each radio goes back to (null = leave it).
    function wanted(type: string, last: var, snapshotValue: var): var {
        const types = root.before?.types;
        if (types)
            return types.includes(type) || types.includes("all") ? snapshotValue : null;
        return last ?? null;
    }
    function restoreRadios(): void {
        const wifi = root.wanted("wlan", root.network?.savedRadio ?? true, root.before?.wifi ?? true);
        if (wifi !== null)
            Quickshell.execDetached(["nmcli", "radio", "wifi", wifi ? "on" : "off"]);
        btRestore.target = root.wanted("bluetooth", root.bluetooth?.saved, root.before?.bt ?? true);
        if (btRestore.target !== null)
            btRestore.restart();
    }

    // The adapter reports its power only once BlueZ has seen the unblock.
    Timer {
        id: btRestore
        property var target: null
        interval: 1500
        onTriggered: {
            const adapter = root.bluetooth?.adapter;
            if (adapter && target !== null && adapter.enabled !== target)
                adapter.enabled = target;
        }
    }

    Component.onCompleted: {
        if (bootMarker.text() !== "")
            return;
        bootMarker.setText("1");
        if (root.savedOn && (Config.data.persist?.airplane ?? true)) {
            Quickshell.execDetached(["rfkill", "block", "all"]);
        } else {
            root.network?.restoreRadio();
            if (root.bluetooth)
                root.bluetooth.pending = true;
        }
    }
    FileView {
        id: bootMarker
        path: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/flicker-radios-restored`
        blockLoading: true
        printErrors: false
    }

    onActiveChanged: {
        if (!arm.armed || !root.available)
            return;
        root.savedOn = root.active;
        if (root.active) {
            if ((root.cfg.dnd ?? false) && root.notifications && !root.notifications.doNotDisturb) {
                root.notifications.doNotDisturb = true;
                root.before = Object.assign({}, root.before ?? {}, { dnd: true });
            }
        } else {
            if (root.before?.dnd && root.notifications)
                root.notifications.doNotDisturb = false;
            root.restoreRadios();
            root.before = null;
        }
        root.write();
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
                root.savedOn = s.on ?? false;
                if (s.types)
                    root.before = { types: s.types, wifi: s.wifi ?? true, bt: s.bt ?? true, dnd: s.dnd ?? false };
            } catch (e) {
                console.warn("Airplane: bad state file, ignoring:", e);
            }
        }
    }
}
