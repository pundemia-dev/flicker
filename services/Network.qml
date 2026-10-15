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

    // Network list for the Quick Settings Wi‑Fi panel, refreshed only while
    // someone wants it (`setScanning`): [{ssid, signal, secure, active,
    // known}], active first, then by signal. `known` = a saved connection
    // named like the SSID (nmcli's default naming).
    property var networks: []
    property bool scanning: false
    property bool listed: false
    // SSID being joined; the last one that failed (wrong password...).
    property string connecting: ""
    property string failed: ""

    function setScanning(on: bool): void {
        if (root.scanning === on)
            return;
        root.scanning = on;
        if (on) {
            Quickshell.execDetached(["nmcli", "device", "wifi", "rescan"]);
            listProc.running = true;
        }
    }

    // Saved / open networks join directly; a new secured one needs `password`.
    function join(ssid: string, password: string): void {
        const net = root.networks.find(n => n.ssid === ssid);
        root.connecting = ssid;
        root.failed = "";
        connectProc.command = net?.known && !password
            ? ["nmcli", "connection", "up", "id", ssid]
            : ["nmcli", "device", "wifi", "connect", ssid].concat(password ? ["password", password] : []);
        connectProc.running = true;
    }

    // nmcli -t: fields split on ':', literal ':' / '\' escaped by '\'.
    function splitTerse(line: string): var {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length)
                cur += line[++i];
            else if (c === ":") {
                out.push(cur);
                cur = "";
            } else
                cur += c;
        }
        out.push(cur);
        return out;
    }

    function parseList(text: string): void {
        const [saved, list] = text.split("\n---\n");
        const known = new Set();
        for (const l of (saved ?? "").split("\n")) {
            const f = root.splitTerse(l);
            if (f[1] === "802-11-wireless")
                known.add(f[0]);
        }
        const bySsid = {};
        for (const l of (list ?? "").split("\n")) {
            const f = root.splitTerse(l);
            const ssid = f[3] ?? "";
            if (!ssid)
                continue;
            const n = { ssid: ssid, signal: parseInt(f[1]) || 0, secure: !!f[2] && f[2] !== "--", active: f[0] === "*", known: known.has(ssid) };
            const o = bySsid[ssid];
            if (!o || n.active || (!o.active && n.signal > o.signal))
                bySsid[ssid] = n;
        }
        root.networks = Object.values(bySsid).sort((a, b) => (b.active - a.active) || (b.signal - a.signal));
        root.listed = true;
    }

    property Process listProc: Process {
        command: ["sh", "-c", "nmcli -t -f NAME,TYPE connection show; echo ---; nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan no"]
        stdout: StdioCollector {
            onStreamFinished: root.parseList(text.trim())
        }
    }

    property Timer scanTimer: Timer {
        interval: Config.data.network.scanMs ?? 4000
        repeat: true
        running: root.scanning
        onTriggered: listProc.running = true
    }

    property Process connectProc: Process {
        onExited: code => {
            if (code !== 0)
                root.failed = root.connecting;
            root.connecting = "";
            root.refresh();
            listProc.running = true;
        }
    }

    function setWifiEnabled(enabled: bool): void {
        wifiEnabled = enabled;
        if (!enabled)
            root.networks = [];
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
        onTriggered: {
            root.refresh();
            if (root.scanning)
                listProc.running = true;
        }
    }

    property Timer pollTimer: Timer {
        interval: Config.data.network.pollMs
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()
}
