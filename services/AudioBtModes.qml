import QtQuick
import Quickshell
import Quickshell.Io

// Bluetooth headset modes pinned in the QS audio panel (Music / Calls pills,
// the pinned one with a lock): per headset address, kept in
// statePath("audio-bt-modes.json"). No pin = Auto: WirePlumber switches to
// calls while an app records from the headset's mic and back after it
// (AudioPolicy.btReturnToMusic too). A pinned headset is held in its mode:
// re-applied when it connects or anything else switches it.
// WirePlumber's own autoswitch would undo a pin (it re-arms its 2 s restore
// whenever ANY capture stream leaves the headset mic) and is ONE global
// setting, so while ANY pin exists it is set false at runtime (never saved);
// with the last pin gone the user's value (saved by Settings → Sound in
// wireplumber's sm-settings, else `audio.btAutoswitchDefault`) comes back.
// Turning it OFF races WirePlumber 0.5.18 (autoswitch-bluetooth-profile.lua
// nils its tables while queued profile events still use them → crash, seen
// live): it is only ever turned off from a tap, `btHoldSettleMs` BEFORE the
// profile switch — never next to a connect or a switch. Owned by
// AudioDevices (`btPins`).
Scope {
    id: root

    required property var devices

    readonly property var cfg: root.devices.cfg ?? ({})
    readonly property string wpKey: "bluetooth.autoswitch-to-headset-profile"
    readonly property string smSettings: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/wireplumber/sm-settings"

    // "AA:BB:…" → "music" | "calls"
    property var pins: ({})
    property bool loaded: false
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

    // A tap on a mode pill: pin that mode (switching to it) — or, on the
    // pinned one, back to Auto (a pinned Calls goes back to music).
    function tap(card: string, address: string, mode: string): void {
        const m = root.devices.btModes(card);
        if (!m || !root.loaded)
            return;
        const a = `${address}`.toUpperCase();
        const next = Object.assign({}, root.pins);
        const unpin = next[a] === mode;
        if (unpin)
            delete next[a];
        else
            next[a] = mode;
        const want = unpin ? (mode === "calls" && m.active === "calls" ? m.music : "") : (m.active !== mode ? (mode === "music" ? m.music : m.calls) : "");
        const wasHolding = root.holding;
        root.setPins(next);
        if (!wasHolding && root.holding) {
            // Off first, the switch once WirePlumber dropped its hooks.
            root.applyHold();
            if (want) {
                deferred.card = card;
                deferred.profile = want;
                deferred.restart();
            }
            return;
        }
        if (want)
            root.devices.setProfile(card, want);
        if (wasHolding && !root.holding)
            root.applyHold();
    }
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
