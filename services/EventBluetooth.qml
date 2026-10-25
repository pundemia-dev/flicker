import QtQuick
import "../config"

// Event source: a Bluetooth device connected -> device glyph (left) +
// its battery (right, live: BlueZ Battery1 often reports a moment after
// the connection; the name until then); disconnected -> the same glyph,
// neutral, name then "Disconnected". Devices already connected at
// start-up are no event. Blueman's own connect / disconnect notifications
// are dropped by the notifications.suppress rules (they would say the
// same thing twice); pairing / file transfer ones stay notifications.
QtObject {
    id: root
    required property var events
    required property var bluetooth

    // Addresses seen connected on the previous pass.
    property var known: []
    // address -> {name, icon} of those, for the disconnect event (a gone
    // device is no longer in connectedDevices).
    property var info: ({})
    // BlueZ objects populate asynchronously: whatever connects within
    // events.startupQuietMs after start is the start-up state, no event.
    property bool armed: false
    property Timer arm: Timer {
        running: true
        interval: Config.data.events.startupQuietMs
        onTriggered: {
            root.known = root.addresses();
            root.info = root.snapshot();
            root.armed = true;
        }
    }

    readonly property var connected: root.bluetooth.connectedDevices
    onConnectedChanged: {
        const now = root.addresses();
        if (!root.armed)
            return;
        const on = Config.data.events.bluetooth ?? true;
        if (on) {
            for (const dev of root.connected)
                if (root.known.indexOf(dev.address) === -1)
                    root.announce(dev);
        }
        for (const addr of root.known)
            if (now.indexOf(addr) === -1) {
                root.events.cancel(`bt:${addr}`);
                if (on && root.info[addr])
                    root.announceGone(addr, root.info[addr].name, root.info[addr].icon);
            }
        root.known = now;
        root.info = root.snapshot();
    }

    function addresses(): var {
        return (root.connected ?? []).map(d => d.address);
    }

    function snapshot(): var {
        const m = {};
        for (const d of root.connected ?? [])
            m[d.address] = { name: d.name || d.deviceName || "", icon: d.icon ?? "" };
        return m;
    }

    function announce(dev: var): void {
        root.events.cancel(`bt:off:${dev.address}`);
        root.events.post({
            key: `bt:${dev.address}`,
            icon: root.glyphFor(dev.icon ?? ""),
            glyph: root.drawnGlyph(dev.icon ?? "", dev.name || dev.deviceName || ""),
            color: "qsBlue",
            text: () => dev.batteryAvailable ? `${Math.round(dev.battery * 100)}%` : (dev.name || dev.deviceName || "")
        });
    }

    // Also IPC `island eventDemo bluetoothOff`.
    function announceGone(address: string, name: string, icon: string): void {
        root.events.post({
            key: `bt:off:${address}`,
            icon: root.glyphFor(icon),
            glyph: root.drawnGlyph(icon, name),
            color: "islandFg",
            texts: name ? [name, I18n.tr("Disconnected")] : [I18n.tr("Disconnected")]
        });
    }

    // Drawn animated glyph (indicators/glyphs): Apple devices by name first
    // (BlueZ reports AirPods and AirPods Max both as audio-headset), then
    // the BlueZ `Icon` kind; the tabler glyph below stays the fallback.
    function drawnGlyph(icon: string, name: string): string {
        const n = name.toLowerCase();
        if (n.indexOf("airpods max") !== -1)
            return "airpodsMax";
        if (n.indexOf("airpods") !== -1 || n.indexOf("buds") !== -1 || n.indexOf("earbuds") !== -1)
            return "airpods";
        if (n.indexOf("homepod") !== -1)
            return "speaker";
        if (icon.indexOf("headset") !== -1 || icon.indexOf("headphone") !== -1)
            return "headphones";
        if (icon.indexOf("audio") !== -1)
            return "speaker";
        if (icon.indexOf("phone") !== -1)
            return "phone";
        if (icon.indexOf("mouse") !== -1)
            return "mouse";
        if (icon.indexOf("keyboard") !== -1)
            return "keyboard";
        if (icon.indexOf("gaming") !== -1)
            return "gamepad";
        if (icon.indexOf("tablet") !== -1)
            return "tablet";
        if (icon.indexOf("computer") !== -1)
            return "laptop";
        if (icon.indexOf("watch") !== -1)
            return "watch";
        return "bluetooth";
    }

    // BlueZ `Icon` (freedesktop device names) -> tabler glyph (fallback).
    function glyphFor(icon: string): string {
        if (icon.indexOf("headset") !== -1 || icon.indexOf("headphone") !== -1)
            return ""; // headphones
        if (icon.indexOf("audio") !== -1)
            return ""; // device-speaker
        if (icon.indexOf("phone") !== -1)
            return ""; // device-mobile
        if (icon.indexOf("mouse") !== -1)
            return ""; // mouse
        if (icon.indexOf("keyboard") !== -1)
            return ""; // keyboard
        if (icon.indexOf("gaming") !== -1)
            return ""; // device-gamepad-2
        if (icon.indexOf("tablet") !== -1)
            return ""; // device-tablet
        if (icon.indexOf("computer") !== -1)
            return ""; // device-laptop
        if (icon.indexOf("watch") !== -1)
            return ""; // device-watch
        return ""; // bluetooth
    }
}
