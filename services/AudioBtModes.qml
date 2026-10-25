import QtQuick
import Quickshell
import Quickshell.Io

// Bluetooth headset modes pinned in the QS audio panel (Music / Calls pills,
// the pinned one with a lock) or on the headset's page in Settings → Sound
// (Mode: Auto / Music / Calls): per headset address, kept in
// statePath("audio-bt-modes.json"). No pin = Auto: WirePlumber switches to
// calls while an app records from the headset's mic and back after it
// (AudioPolicy.btReturnToMusic too). A pinned headset is held in its mode:
// re-applied when it connects or anything else switches it.
// WirePlumber's own autoswitch would undo a pin (it re-arms its 2 s restore
// whenever ANY capture stream leaves the headset mic) and is ONE global
// setting, so while ANY pin exists it is set false at runtime (never saved);
// with the last pin gone the user's value (saved by Settings → Sound in
// wireplumber's sm-settings, else `audio.btAutoswitchDefault`) comes back.
// HACK (WirePlumber 0.5.18 crash, report draft in
// temp/upstream-reports/03-…): turning the setting OFF races
// autoswitch-bluetooth-profile.lua (it nils its tables while queued profile
// events still use them → core dump, seen live), so it is only ever turned
// off from a tap, `btHoldSettleMs` BEFORE the profile switch (the `deferred`
// timer), and held while ANY pin exists — never next to a connect or a
// switch. Remove when a WirePlumber release keeps those tables (or nil-guards
// them): switch directly in setMode(), and hold only while a pinned headset
// is connected. Owned by AudioDevices (`btPins`).
Scope {
    id: root

    required property var devices

    readonly property var cfg: root.devices.cfg ?? ({})
    readonly property string wpKey: "bluetooth.autoswitch-to-headset-profile"
    readonly property string smSettings: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/wireplumber/sm-settings"

    // "AA:BB:…" → "music" | "calls"
    property var pins: ({})
    property bool loaded: false
    // HACK (WirePlumber 0.5.18 crash, see the header): any pin, not
    // "a pinned headset is connected" — that would flip the setting at a connect.
    readonly property bool holding: Object.keys(root.pins).length > 0
    function pinOf(address: string): string {
        return root.pins[`${address}`.toUpperCase()] ?? "";
    }
    function addressOf(card: var): string {
        return `${card?.properties?.["api.bluez5.address"] ?? ""}`.toUpperCase();
    }

    FileView {
        id: file
        path: Quickshell.statePath("audio-bt-modes.json")
        printErrors: false
        onLoaded: root.restore(file.text())
        onLoadFailed: root.restore("{}")
    }
    function restore(text: string): void {
        try {
            root.pins = JSON.parse(text) ?? {};
        } catch (e) {
            root.pins = {};
        }
        root.loaded = true;
        // Shell start: a quiet moment, bring the setting in line.
        root.applyHold();
    }
    function setPins(next: var): void {
        root.pins = next;
        file.setText(JSON.stringify(next, null, 2));
    }

    // "auto" | "music" | "calls" of a headset (Settings → Sound device page).
    function modeOf(address: string): string {
        return root.pinOf(address) || "auto";
    }
    function cardOf(address: string): var {
        const a = `${address}`.toUpperCase();
        return (root.devices.pulse.cards ?? []).find(c => (c.name ?? "").startsWith("bluez_") && root.addressOf(c) === a) ?? null;
    }

    // A tap on a mode pill (QS panel): pin that mode — or, on the pinned
    // one, back to Auto.
    function tap(card: string, address: string, mode: string): void {
        root.setMode(address, root.pinOf(address) === mode ? "auto" : mode);
    }

    // Pin a mode / back to Auto, also for a headset that is not connected
    // (it takes the mode when it connects). A connected one switches to it;
    // Auto out of a pinned Calls goes back to music.
    function setMode(address: string, mode: string): void {
        if (!root.loaded)
            return;
        const a = `${address}`.toUpperCase();
        const prev = root.modeOf(a);
        if (a === "" || prev === mode)
            return;
        const next = Object.assign({}, root.pins);
        if (mode === "auto")
            delete next[a];
        else
            next[a] = mode;
        const c = root.cardOf(a);
        const m = c ? root.devices.btModes(c.name) : null;
        const want = !m ? "" : mode === "auto" ? (prev === "calls" && m.active === "calls" ? m.music : "")
            : (m.active !== mode ? (mode === "music" ? m.music : m.calls) : "");
        const wasHolding = root.holding;
        root.setPins(next);
        if (!wasHolding && root.holding) {
            // Off first, the switch once WirePlumber dropped its hooks.
            root.applyHold();
            if (want) {
                deferred.card = c.name;
                deferred.profile = want;
                deferred.restart();
            }
            return;
        }
        if (want)
            root.devices.setProfile(c.name, want);
        if (wasHolding && !root.holding)
            root.applyHold();
    }
    // HACK (WirePlumber 0.5.18 crash): the profile switch waits
    // btHoldSettleMs after the setting went off.
    Timer {
        id: deferred
        property string card: ""
        property string profile: ""
        interval: root.cfg.btHoldSettleMs ?? 800
        onTriggered: root.devices.setProfile(card, profile)
    }

    // Connected headsets with a pin, kept in their mode (after a connect, or
    // a switch by anyone else). A switch in flight is left alone.
    readonly property var pinned: (root.devices.pulse.cards ?? []).filter(c => (c.name ?? "").startsWith("bluez_") && root.pinOf(root.addressOf(c)) !== "")
    onPinnedChanged: Qt.callLater(root.enforce)
    function enforce(): void {
        if (deferred.running)
            return;
        for (const c of root.pinned) {
            if ((root.devices.switching[c.name]?.until ?? 0) > Date.now())
                continue;
            const m = root.devices.btModes(c.name);
            const want = root.pinOf(root.addressOf(c));
            if (m && m.active !== want)
                root.devices.setProfile(c.name, want === "music" ? m.music : m.calls);
        }
    }

    // Runtime value only; skipped when it is already what we want.
    property string applied: ""
    function applyHold(): void {
        const target = root.holding ? "off" : "user";
        if (root.applied === target)
            return;
        root.applied = target;
        holdProc.running = false;
        holdProc.command = root.holding
            ? ["wpctl", "settings", root.wpKey, "false"]
            : ["sh", "-c", 'v=$(sed -n "s/^$1=//p" "$2" 2>/dev/null); [ -n "$v" ] && wpctl settings "$1" "$v" || wpctl settings "$1" "$3"', "sh", root.wpKey, root.smSettings, `${root.cfg.btAutoswitchDefault ?? true}`];
        holdProc.running = true;
    }
    // Settings → Sound saved the key (that set the runtime value too).
    function reassert(): void {
        root.applied = "";
        if (root.holding)
            root.applyHold();
    }
    Process {
        id: holdProc
    }
}
