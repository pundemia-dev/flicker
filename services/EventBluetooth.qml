import QtQuick
import "../config"

// Event source: a Bluetooth device connected -> device glyph (left) +
// its battery (right, live: BlueZ Battery1 often reports a moment after
// the connection; the name until then). Devices already connected at
// start-up are no event. Blueman's own "Connected" notification is dropped
// by the notifications.suppress rules (it would say the same thing twice).
QtObject {
    id: root
    required property var events
    required property var bluetooth

    // Addresses seen connected on the previous pass.
    property var known: []
    // BlueZ objects populate asynchronously: whatever connects within
    // events.startupQuietMs after start is the start-up state, no event.
    property bool armed: false
    property Timer arm: Timer {
        running: true
        interval: Config.data.events.startupQuietMs
        onTriggered: {
            root.known = root.addresses();
            root.armed = true;
        }
    }

    readonly property var connected: root.bluetooth.connectedDevices
    onConnectedChanged: {
        const now = root.addresses();
        if (!root.armed)
            return;
        if (Config.data.events.bluetooth ?? true) {
            for (const dev of root.connected)
                if (root.known.indexOf(dev.address) === -1)
                    root.announce(dev);
        }
        for (const addr of root.known)
            if (now.indexOf(addr) === -1)
                root.events.cancel(`bt:${addr}`);
        root.known = now;
    }

    function addresses(): var {
        return (root.connected ?? []).map(d => d.address);
    }

    function announce(dev: var): void {
        root.events.post({
            key: `bt:${dev.address}`,
            icon: root.glyphFor(dev.icon ?? ""),
            color: "qsBlue",
            text: () => dev.batteryAvailable ? `${Math.round(dev.battery * 100)}%` : (dev.name || dev.deviceName || "")
        });
    }

    // BlueZ `Icon` (freedesktop device names) -> tabler glyph.
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
