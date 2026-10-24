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
    // NetworkManager's connectivity state (full / limited / portal / none /
    // unknown); "portal" = a captive portal wants a sign-in.
    property string connectivity: "unknown"
    readonly property bool portal: root.wifiConnected && root.connectivity === "portal"

    // Network list for the Quick Settings Wi‑Fi panel, refreshed only while
    // someone wants it (`setScanning`): [{ssid, signal, secure, enterprise,
    // active, known}], active first, then by signal. `known` = a saved
    // profile for that SSID (`saved`, matched by 802-11-wireless.ssid, not
    // by the profile name).
    property var networks: []
    property bool scanning: false
    property bool listed: false
    // Saved Wi‑Fi profiles by SSID: {uuids: [...], keyMgmt} (wpa-psk / sae /
    // wpa-eap / "" = open).
    property var saved: ({})
    // `saved` loaded once: until then the list is held back (every network
    // would read as unsaved and re-sort into its section a moment later).
    property bool savedReady: false
    // A rescan was asked and its results are not in yet.
    property bool rescanning: false
    // SSID being joined; the last one that failed and why (`failReason`:
    // password / notfound / timeout / ip / other, `failText` = nmcli's own
    // line for "other").
    property string connecting: ""
    property string failed: ""
    property string failReason: ""
    property string failText: ""
    property bool disconnecting: false
    // Current link (`loadDetails`): {ip, gateway, dns, mac, band, channel,
    // rate, security, bssid}; null until loaded.
    property var details: null
    // `loadShare(ssid)`: {ssid, password, qr (data URL)}; null until loaded.
    property var share: null
    // Ping / speed test of the current link (Details; same as the VPN
    // panel's, through whatever route is up). pingMs: -1 none, -2 timeout;
    // speed: { down, up } Mbit/s or null; speedError: "" | missing | failed.
    property bool pinging: false
    property int pingMs: -1
    property bool speedtesting: false
    property var speed: null
    property string speedError: ""
    // Results belong to the link they were measured on.
    onWifiSsidChanged: {
        root.pingMs = -1;
        root.speed = null;
        root.speedError = "";
    }

    readonly property string script: Quickshell.shellDir + "/scripts/network/wifi.sh"

    function setScanning(on: bool): void {
        if (root.scanning === on)
            return;
        root.scanning = on;
        if (on)
            root.rescan();
    }

    // NM rescans rarely while connected: the panel asks every `rescanMs`
    // (NM refuses scans that come too fast; harmless).
    function rescan(): void {
        root.rescanning = true;
        savedProc.running = true;
        Quickshell.execDetached(["nmcli", "device", "wifi", "rescan"]);
        rescanSettle.restart();
        listProc.running = true;
    }

    // Saved / open networks join directly; a new secured one needs
    // `password`; a saved one given a password gets it stored first (the
    // router's password changed). opts: {hidden: bool, identity: string
    // (WPA‑Enterprise user name)}.
    function join(ssid: string, password: string, opts: var): void {
        const o = opts ?? {};
        const net = root.networks.find(n => n.ssid === ssid);
        const s = root.saved[ssid];
        const uuid = s?.uuids[0] ?? "";
        const eap = (net?.enterprise ?? false) || s?.keyMgmt === "wpa-eap";
        root.connecting = ssid;
        root.failed = "";
        if (eap && password)
            connectProc.command = [root.script, "eap", ssid, o.identity ?? "", password].concat(uuid ? [uuid] : []);
        else if (uuid && password)
            connectProc.command = [root.script, "psk", uuid, password];
        else if (uuid)
            connectProc.command = ["nmcli", "-w", "40", "connection", "up", "uuid", uuid];
        else if (o.hidden)
            connectProc.command = [root.script, "hidden", ssid, password];
        else
            connectProc.command = ["nmcli", "-w", "40", "device", "wifi", "connect", ssid]
                .concat(password ? ["password", password] : []);
        connectProc.running = true;
    }

    function disconnect(): void {
        root.disconnecting = true;
        downProc.running = true;
    }

    function forget(ssid: string): void {
        const uuids = root.saved[ssid]?.uuids ?? [];
        if (uuids.length === 0)
            return;
        if (root.failed === ssid)
            root.failed = "";
        forgetProc.command = [root.script, "forget"].concat(uuids);
        forgetProc.running = true;
    }

    function loadDetails(): void {
        detailsProc.running = true;
    }

    function testPing(): void {
        if (root.pinging)
            return;
        root.pinging = true;
        pingProc.running = true;
    }

    function testSpeed(): void {
        if (root.speedtesting)
            return;
        root.speedtesting = true;
        root.speedError = "";
        speedProc.running = true;
    }

    function loadShare(ssid: string): void {
        const s = root.saved[ssid];
        if (!s)
            return;
        root.share = null;
        shareProc.ssid = ssid;
        shareProc.command = [root.script, "share", s.uuids[0], s.keyMgmt === "sae" ? "SAE" : "WPA", ssid];
        shareProc.running = true;
    }

    // Captive portal: any plain-http page gets redirected to the sign-in.
    function openPortal(): void {
        Quickshell.execDetached(["xdg-open", Config.data.network.portalUrl ?? "http://neverssl.com"]);
    }

    function openSettings(): void {
        Quickshell.execDetached((Config.data.launcher?.apps?.terminal ?? ["kitty"]).concat(["nmtui"]));
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

    // "key:value" line of nmcli -t multiline output (the value may hold ':').
    function terseValue(line: string): string {
        return root.splitTerse(line).slice(1).join(":");
    }

    function parseSaved(text: string): void {
        const out = {};
        for (const block of text.split(/\n\s*\n/)) {
            let uuid = "", ssid = "", km = "";
            for (const l of block.split("\n")) {
                if (l.startsWith("connection.uuid:"))
                    uuid = root.terseValue(l);
                else if (l.startsWith("802-11-wireless.ssid:"))
                    ssid = root.terseValue(l);
                else if (l.startsWith("802-11-wireless-security.key-mgmt:"))
                    km = root.terseValue(l);
            }
            if (!uuid || !ssid)
                continue;
            if (!out[ssid])
                out[ssid] = { uuids: [], keyMgmt: km };
            out[ssid].uuids.push(uuid);
        }
        root.saved = out;
        root.savedReady = true;
        root.parseList(root.lastList);
    }

    property string lastList: ""
    function parseList(text: string): void {
        root.lastList = text;
        if (!root.savedReady)
            return;
        const bySsid = {};
        for (const l of text.split("\n")) {
            const f = root.splitTerse(l);
            const ssid = f[3] ?? "";
            if (!ssid)
                continue;
            const sec = f[2] ?? "";
            const n = {
                ssid: ssid, signal: parseInt(f[1]) || 0, secure: !!sec && sec !== "--",
                enterprise: sec.includes("802.1X"), active: f[0] === "*", known: !!root.saved[ssid]
            };
            const o = bySsid[ssid];
            if (!o || n.active || (!o.active && n.signal > o.signal))
                bySsid[ssid] = n;
        }
        root.networks = Object.values(bySsid).sort((a, b) => (b.active - a.active) || (b.signal - a.signal));
        root.listed = true;
    }

    // nmcli's error line → a reason the panel can word.
    function reasonOf(err: string): string {
        const t = err.toLowerCase();
        if (/secrets were required|no secrets|802\.1x supplicant|supplicant-disconnect|password|psk/.test(t))
            return "password";
        if (/no network with ssid|could not be found|not found/.test(t))
            return "notfound";
        if (/timeout|timed out/.test(t))
            return "timeout";
        if (/ip configuration|dhcp/.test(t))
            return "ip";
        return "other";
    }

    property Process listProc: Process {
        command: ["nmcli", "-t", "-f", "IN-USE,SIGNAL,SECURITY,SSID", "device", "wifi", "list", "--rescan", "no"]
        stdout: StdioCollector {
            onStreamFinished: root.parseList(text.trim())
        }
    }

    property Process savedProc: Process {
        command: [root.script, "saved"]
        stdout: StdioCollector {
            onStreamFinished: root.parseSaved(text.trim())
        }
    }

    property Timer scanTimer: Timer {
        interval: Config.data.network.scanMs ?? 4000
        repeat: true
        running: root.scanning
        onTriggered: listProc.running = true
    }

    property Timer rescanTimer: Timer {
        interval: Config.data.network.rescanMs ?? 15000
        repeat: true
        running: root.scanning && root.wifiEnabled
        onTriggered: root.rescan()
    }

    // A scan takes a few seconds; list again once it is likely done.
    property Timer rescanSettle: Timer {
        interval: 3500
        onTriggered: {
            root.rescanning = false;
            listProc.running = true;
        }
    }

    property Process connectProc: Process {
        stderr: StdioCollector {
            id: connectErr
        }
        onExited: code => {
            if (code !== 0) {
                // nmcli ends with a "Hint: use journalctl..." line: the
                // reason is the "Error:" one.
                const lines = connectErr.text.trim().split("\n").filter(l => l.trim() && !l.startsWith("Hint:"));
                const err = lines.find(l => l.startsWith("Error:")) ?? lines.pop() ?? "";
                root.failReason = root.reasonOf(err);
                root.failText = err.replace(/^Error:\s*/, "").replace(/^Connection activation failed:\s*/, "")
                    .replace(/^No reason given\.?$/i, "");
                root.failed = root.connecting;
            }
            root.connecting = "";
            root.refresh();
            savedProc.running = true;
            listProc.running = true;
        }
    }

    property Process downProc: Process {
        command: [root.script, "down"]
        onExited: () => {
            root.disconnecting = false;
            root.refresh();
            listProc.running = true;
        }
    }

    property Process forgetProc: Process {
        onExited: () => {
            savedProc.running = true;
            root.refresh();
        }
    }

    property Process detailsProc: Process {
        command: [root.script, "details"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [dev, ap] = text.trim().split("\n---\n");
                const d = { ip: "", gateway: "", dns: [], mac: "", band: "", channel: "", rate: "", security: "", bssid: "" };
                for (const l of (dev ?? "").split("\n")) {
                    const v = l.slice(l.indexOf(":") + 1);
                    if (l.startsWith("IP4.ADDRESS") && !d.ip)
                        d.ip = v;
                    else if (l.startsWith("IP4.GATEWAY"))
                        d.gateway = v;
                    else if (l.startsWith("IP4.DNS"))
                        d.dns.push(v);
                    else if (l.startsWith("GENERAL.HWADDR"))
                        d.mac = v;
                }
                const f = root.splitTerse(ap ?? "");
                const mhz = parseInt(f[2]) || 0;
                d.channel = f[1] ?? "";
                d.band = mhz >= 5925 ? "6 GHz" : mhz >= 4900 ? "5 GHz" : mhz > 0 ? "2.4 GHz" : "";
                d.rate = f[3] ?? "";
                d.security = f[4] && f[4] !== "--" ? f[4] : "";
                d.bssid = f[5] ?? "";
                d.dns = d.dns.join(", ");
                root.details = d;
            }
        }
    }

    property Process pingProc: Process {
        command: [root.script, "ping"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/OK:(\d+)/);
                root.pingMs = m ? +m[1] : -2;
                root.pinging = false;
            }
        }
    }

    property Process speedProc: Process {
        command: [root.script, "speedtest"]
        stdout: StdioCollector {
            onStreamFinished: {
                const num = re => (text.match(re) ?? [])[1] ?? "";
                const down = num(/Download:\s*([\d.]+)/);
                const up = num(/Upload:\s*([\d.]+)/);
                if (text.includes("ERR_MISSING"))
                    root.speedError = "missing";
                else if (!down && !up)
                    root.speedError = "failed";
                else
                    root.speed = { down: Math.round(+down), up: Math.round(+up) };
                root.speedtesting = false;
            }
        }
    }

    property Process shareProc: Process {
        property string ssid: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const nl = text.indexOf("\n");
                const qr = text.slice(nl + 1).trim();
                root.share = {
                    ssid: shareProc.ssid,
                    password: nl >= 0 ? text.slice(0, nl) : "",
                    qr: qr ? "data:image/png;base64," + qr : ""
                };
            }
        }
    }

    function setWifiEnabled(enabled: bool): void {
        root.savedRadio = enabled;
        radioState.write({ wifi: enabled });
        root.applyRadio(enabled);
    }

    // Switches the radio without saving it as the user's choice (Airplane,
    // the start-up restore).
    function applyRadio(enabled: bool): void {
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

    // Line 1 = radio, 2 = connectivity, 3 = the active network (if any).
    property Process wifiProc: Process {
        command: ["sh", "-c", "nmcli -t -f WIFI g | head -n1; nmcli networking connectivity; nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi | grep '^yes:' | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                root.wifiEnabled = (lines[0] ?? "").trim() === "enabled";
                root.connectivity = (lines[1] ?? "").trim() || "unknown";
                const active = lines[2] ?? "";
                if (!active || !root.wifiEnabled) {
                    root.wifiConnected = false;
                    root.wifiStrength = 0;
                    root.wifiSsid = "";
                    return;
                }
                const parts = root.splitTerse(active);
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

    // The switch's last state (card / panel) persists in statePath("wifi.json")
    // (`savedRadio`: true / false / null = never tapped). Airplane re-applies it
    // once per login (restoreRadio), unless it restores Airplane Mode itself. Only taps
    // here are saved: Airplane Mode and nmcli from elsewhere leave it alone.
    property var savedRadio: null
    property StateFile radioState: StateFile {
        name: "wifi.json"
        onLoaded: {
            const s = radioState.read();
            if (typeof s.wifi === "boolean")
                root.savedRadio = s.wifi;
        }
    }

    // Reads the file itself: Airplane calls this from its onCompleted, which
    // may run before radioState's onLoaded.
    function restoreRadio(): void {
        const s = radioState.read();
        if (typeof s.wifi === "boolean")
            root.savedRadio = s.wifi;
        if (root.savedRadio === null || !(Config.data.persist?.wifi ?? true))
            return;
        root.applyRadio(root.savedRadio);
    }

    Component.onCompleted: root.refresh()
}
