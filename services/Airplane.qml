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
// nothing the mode blocked is soft-blocked any more; without one (the block came from
// elsewhere) "off" unblocks everything and the radios follow their own
// last switch state (Network `savedRadio` / Bluetooth `saved`). Wi‑Fi is
// switched back on in NM after ANY exit (Fn key, rfkill elsewhere too): an
// rfkill unblock alone may leave NM's radio off. A partial exit (only
// Bluetooth unblocked) restores just the unblocked radios; the rest follow
// when they are unblocked (`exiting`).
// Only state changes of present devices count as the mode switching
// (rfkill op 2): devices vanishing at shutdown or re-listed after a
// `rfkill event` restart can leave every remaining one blocked for a
// moment, which is no Airplane Mode (no save, event or restore).
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
    // rfkill op of the event that last changed `devices` (0 add, 1 del, 2 change).
    property int lastOp: 0
    // Left the mode, some radios not restored yet (`restoredTypes` = done).
    property bool exiting: false
    property var restoredTypes: []

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
        stateFile.write(Object.assign({ on: root.savedOn }, root.before ?? {}));
    }

    // After an exit: what each radio goes back to (null = leave it).
    function wanted(type: string, last: var, snapshotValue: var): var {
        const types = root.before?.types;
        if (types)
            return types.includes(type) || types.includes("all") ? snapshotValue : null;
        return last ?? null;
    }
    function unblocked(type: string): bool {
        const code = root.typeNames.indexOf(type);
        return root.list.some(d => d.type === code && !d.soft && !d.hard);
    }
    // Restores each radio once it is unblocked; ends the exit (and drops
    // the snapshot) when nothing the mode blocked is soft-blocked.
    function settleExit(): void {
        if (!root.exiting || root.active)
            return;
        if (!root.restoredTypes.includes("wlan") && root.unblocked("wlan")) {
            root.restoredTypes = [...root.restoredTypes, "wlan"];
            const wifi = root.wanted("wlan", root.network?.savedRadio ?? true, root.before?.wifi ?? true);
            if (wifi !== null)
                root.network?.applyRadio(wifi);
        }
        if (!root.restoredTypes.includes("bluetooth") && root.unblocked("bluetooth")) {
            root.restoredTypes = [...root.restoredTypes, "bluetooth"];
            btRestore.target = root.wanted("bluetooth", root.bluetooth?.saved, root.before?.bt ?? true);
            if (btRestore.target !== null)
                btRestore.restart();
        }
        // Types that were off before the mode stay blocked: not waited for.
        const types = root.before?.types;
        const waited = d => !types || types.includes("all") || types.includes(root.typeNames[d.type]);
        if (root.list.every(d => !d.soft || !waited(d))) {
            root.exiting = false;
            root.restoredTypes = [];
            root.before = null;
            root.write();
        }
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

    // Read here, not only in onLoaded: whether the child's load lands
    // before this onCompleted is not guaranteed.
    function load(): void {
        const s = stateFile.read();
        root.savedOn = s.on === true;
        root.before = Array.isArray(s.types)
            ? { types: s.types, wifi: s.wifi ?? true, bt: s.bt ?? true, dnd: s.dnd ?? false } : null;
    }
    Component.onCompleted: {
        root.load();
        if (!bootMarker.claim())
            return;
        if (root.savedOn && (Config.data.persist?.airplane ?? true)) {
            Quickshell.execDetached(["rfkill", "block", "all"]);
        } else {
            // Not re-applied: forget it, or turning persist.airplane back
            // on later would block everything at the next login.
            if (root.savedOn) {
                root.savedOn = false;
                root.before = null;
                root.write();
            }
            root.network?.restoreRadio();
            if (root.bluetooth && (Config.data.persist?.bluetooth ?? true))
                root.bluetooth.pending = true;
        }
    }
    LoginOnce {
        id: bootMarker
        name: "radios"
    }

    // State bookkeeping runs from the first op-2 change (an exit during
    // startupQuietMs must still be saved and restore the radios); DND and the
    // event wait for `arm`. A hardware kill switch alone is no saved mode:
    // `savedOn` needs every device soft-blocked.
    onActiveChanged: {
        if (!root.available || root.lastOp !== 2)
            return;
        root.savedOn = root.active && root.list.every(d => d.soft);
        if (root.active) {
            root.exiting = false;
            root.restoredTypes = [];
            if (arm.armed && (root.cfg.dnd ?? false) && root.notifications && !root.notifications.doNotDisturb) {
                root.notifications.doNotDisturb = true;
                root.before = Object.assign({}, root.before ?? {}, { dnd: true });
            }
        } else {
            if (root.before?.dnd && root.notifications)
                root.notifications.doNotDisturb = false;
            if (root.before)
                root.before = Object.assign({}, root.before, { dnd: false });
            root.exiting = true;
            root.restoredTypes = [];
            root.settleExit();
        }
        root.write();
        if (!arm.armed)
            return;
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
                root.lastOp = +m[3];
                root.devices = next;
                if (root.lastOp === 2)
                    root.settleExit();
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

    StateFile {
        id: stateFile
        name: "airplane.json"
        onLoaded: root.load()
    }
}
