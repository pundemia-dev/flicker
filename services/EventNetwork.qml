import QtQuick
import "../config"

// Event source: Wi‑Fi joined / switched / lost (WifiGlyph). Network polls
// nmcli, so a roam between two networks may pass through "disconnected"
// for one poll: the state must hold `events.wifiSettleMs` before it counts,
// and only a change against the last ANNOUNCED state is an event. Joined
// or switched = the arcs open + the SSID; lost = the arcs go out +
// "Disconnected" (or "Wi‑Fi off" when the radio was switched off).
QtObject {
    id: root
    required property var events
    required property var network

    readonly property string state: root.network.wifiConnected ? `on:${root.network.wifiSsid}` : "off"
    property string announced: ""
    property bool armed: false
    property Timer arm: Timer {
        running: true
        interval: Config.data.events.startupQuietMs
        onTriggered: {
            root.announced = root.state;
            root.armed = true;
        }
    }
    property Timer settle: Timer {
        interval: Config.data.events.wifiSettleMs ?? 1500
        onTriggered: root.commit()
    }
    onStateChanged: if (root.armed) root.settle.restart()

    function commit(): void {
        const now = root.state;
        if (now === root.announced)
            return;
        root.announced = now;
        if (!(Config.data.events.wifi ?? true))
            return;
        root.announce(root.network.wifiConnected, root.network.wifiSsid, root.network.wifiEnabled);
    }

    // Also IPC `island eventDemo wifi|wifiLost`.
    function announce(connected: bool, ssid: string, radioOn: bool): void {
        root.events.cancel(connected ? "wifi:lost" : "wifi:on");
        root.events.post(connected ? {
            key: "wifi:on",
            glyph: "wifi",
            icon: "",
            color: "qsBlue",
            text: ssid || I18n.tr("Connected")
        } : {
            key: "wifi:lost",
            glyph: "wifi",
            glyphArgs: { lost: true },
            icon: "",
            color: "islandFg",
            text: radioOn ? I18n.tr("Disconnected") : I18n.tr("Wi‑Fi off")
        });
    }
}
