import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

QtObject {
    id: root

    property bool wifiEnabled: false
    property bool wifiConnected: false
    property int wifiStrength: 0
    property string wifiSsid: ""
    property bool hotspotEnabled: false
    readonly property string hotspotName: Config.data.network.hotspotName

    function setWifiEnabled(enabled: bool): void {
        wifiEnabled = enabled;
        Quickshell.execDetached(["nmcli", "radio", "wifi", enabled ? "on" : "off"]);
        refreshTimer.restart();
    }

    function toggleWifi(): void { setWifiEnabled(!wifiEnabled); }

    function setHotspotEnabled(enabled: bool): void {
        if (enabled)
            hotspotProc.command = ["nmcli", "device", "wifi", "hotspot"];
        else
            hotspotProc.command = ["sh", "-c", `nmcli connection down ${root.hotspotName} 2>/dev/null || nmcli connection down ${root.hotspotName.toLowerCase()} 2>/dev/null`];
        hotspotProc.running = true;
    }

    function refresh(): void {
        wifiProc.running = true;
        hotspotCheckProc.running = true;
    }

    property Process wifiProc: Process {
        command: ["sh", "-c", "nmcli -t -f WIFI g | head -n1; nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi | grep '^yes:' | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                root.wifiEnabled = (lines[0] ?? "").trim() === "enabled";
                const active = lines[1] ?? "";
                if (!active || !root.wifiEnabled) {
                    root.wifiConnected = false;
                    root.wifiStrength = 0;
                    root.wifiSsid = "";
                    return;
                }
                const parts = active.split(":");
                root.wifiConnected = true;
                root.wifiSsid = parts[1] ?? "";
                root.wifiStrength = Math.max(0, Math.min(100, parseInt(parts[2] || "0")));
            }
        }
    }

    property Process hotspotCheckProc: Process {
        command: ["sh", "-c", `nmcli -t -f GENERAL.STATE con show ${root.hotspotName} 2>/dev/null | grep -q activated && echo on || echo off`]
        stdout: StdioCollector {
            onStreamFinished: root.hotspotEnabled = text.trim() === "on"
        }
    }

    property Process hotspotProc: Process {
        onExited: () => refreshTimer.restart()
    }

    property Timer refreshTimer: Timer {
        interval: 600
        onTriggered: root.refresh()
    }

    property Timer pollTimer: Timer {
        interval: Config.data.network.pollMs
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()
}
