import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// VPN (QS card `vpn` + its panel, IPC `island vpn`): sing-box as the system
// unit (+ xray.service for the gRPC / XHTTP nodes), driven by
// scripts/vpn/vpn.sh (ported from the dots-hyprland "ii" Vpn service). State = one `vpn.sh state` JSON poll (every
// quicksettings.vpn.pollMs, faster while a change settles): unit state, an
// HTTP probe through it, the nodes of the config's selector and the active
// one. One operation at a time (`busy`); start / stop go through systemd's
// polkit check (no prompt once `vpn.sh setup` installed the rule), node
// switch and subscription install through pkexec (the shell's polkit agent
// asks). Ping / speed test are separate and may run alongside.
// Kill switch (`vpn.sh killswitch`): an nftables block raised with sing-box
// that outlives a crash; only a stop (setActive(false) / release()) lowers it.
Scope {
    id: root
    required property var events

    readonly property var cfg: Config.data.quicksettings.vpn ?? ({})
    readonly property string script: Quickshell.shellDir + "/scripts/vpn/vpn.sh"

    // Last `state` poll.
    property bool installed: false
    property string unit: "inactive"
    // Autostart at boot (systemctl is-enabled).
    property bool enabled: false
    property bool online: false
    property string profile: ""
    property var profiles: []
    property bool subscription: false
    // Kill switch on; blocking = its table is up while sing-box is not
    // (crashed / failed): no traffic until the VPN is back or released.
    property bool killswitch: false
    property bool blocking: false
    property bool polled: false

    // Running operation: "" | start | stop | restart | autostart | killswitch
    // | select | update | subscribe.
    property string busy: ""
    property string selecting: ""
    property string error: ""
    // Up but the probe through it has failed for quicksettings.vpn.stallMs:
    // the node is dead (status "offline" instead of an endless "connecting").
    property bool stalled: false

    property bool pinging: false
    property int pingMs: -1
    property bool speedtesting: false
    // { down, up } strings (Mbit/s) or null; speedError: "" | missing | failed.
    property var speed: null
    property string speedError: ""

    readonly property bool available: root.installed
    // Switched on (wanted up), whatever the probe says.
    readonly property bool on: root.busy === "start" || root.busy === "restart" || (root.busy !== "stop"
        && (root.unit === "active" || root.unit === "activating" || root.unit === "reloading"))
    // inactive | connecting | active | offline | disconnecting | failed |
    // blocked (off, kill switch holding traffic) | unavailable
    readonly property string status: {
        if (!root.installed)
            return root.polled ? "unavailable" : "inactive";
        if (root.busy === "stop" || root.unit === "deactivating")
            return "disconnecting";
        if (root.on) {
            const idle = root.busy === "" || root.busy === "autostart";
            if (root.unit === "active" && idle)
                return root.online ? "active" : root.stalled ? "offline" : "connecting";
            return "connecting";
        }
        if (root.blocking)
            return "blocked";
        return root.unit === "failed" ? "failed" : "inactive";
    }

    function toggle(): void {
        root.setActive(!root.on);
    }
    function setActive(up: bool): void {
        if (!root.installed || root.busy !== "")
            return;
        root.run(up ? "start" : "stop", [up ? "start" : "stop"]);
    }
    function restart(): void {
        if (root.installed && root.busy === "")
            root.run("restart", ["restart"]);
    }
    function setAutostart(on: bool): void {
        if (root.installed && root.busy === "" && on !== root.enabled)
            root.run("autostart", [on ? "enable" : "disable"]);
    }
    function setKillswitch(on: bool): void {
        if (root.installed && root.busy === "" && on !== root.killswitch)
            root.run("killswitch", ["killswitch", on ? "on" : "off"]);
    }
    // Lift a kill switch left blocking by a dead sing-box (a plain stop).
    function release(): void {
        if (root.busy === "" && root.blocking)
            root.run("stop", ["stop"]);
    }
    // The unit's journal, followed, in the user's terminal.
    function openLogs(): void {
        Quickshell.execDetached((Config.data.launcher?.apps?.terminal ?? ["kitty"]).concat(["journalctl", "-f", "-u", "sing-box", "-u", "xray", "-n", "200"]));
    }
    function select(tag: string): void {
        if (root.busy !== "" || tag === "" || tag === root.profile)
            return;
        root.selecting = tag;
        root.run("select", ["select", tag]);
    }
    function subscribe(url: string): void {
        if (root.busy === "" && url.trim() !== "")
            root.run("subscribe", ["subscribe", url.trim()]);
    }
    function updateSubscription(): void {
        if (root.busy === "" && root.subscription)
            root.run("update", ["update"]);
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
    function refresh(): void {
        if (!stateProc.running)
            stateProc.running = true;
    }

    function run(kind: string, args: var): void {
        root.busy = kind;
        root.error = "";
        op.kind = kind;
        op.arg = args[1] ?? "";
        op.command = [root.script, ...args];
        op.running = true;
    }

    Process {
        id: op
        property string kind: ""
        property string arg: ""
        stdout: StdioCollector {
            id: opOut
        }
        onExited: code => {
            const err = opOut.text.split("\n").find(l => l.startsWith("ERR:"));
            root.busy = "";
            root.selecting = "";
            if (code !== 0) {
                // 126/127 = pkexec: the prompt was dismissed / not authorized.
                root.error = err ? err.substring(4) : code === 126 || code === 127 ? "cancelled" : `exit ${code}`;
                console.info("[vpn]", op.kind, "failed:", root.error);
                if (code !== 126 && code !== 127)
                    root.post("vpn:error", "accentRed", op.kind === "subscribe" || op.kind === "update"
                        ? I18n.tr("Subscription failed") : I18n.tr("VPN failed"));
            } else if (op.kind === "subscribe" || op.kind === "update") {
                root.post("vpn:sub", "qsBlue", I18n.tr("Subscription updated"));
            } else if (op.kind === "select" && root.up) {
                root.events.cancel("vpn:off");
                root.post("vpn:on", "qsBlue", `VPN · ${op.arg}`);
            }
            root.stalled = false;
            root.refresh();
            settle.restart();
        }
    }

    Process {
        id: stateProc
        command: [root.script, "state"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(text);
                    root.installed = s.installed;
                    root.unit = s.unit || "inactive";
                    root.enabled = s.enabled ?? false;
                    root.online = s.online;
                    root.profile = s.profile ?? "";
                    if (JSON.stringify(s.profiles) !== JSON.stringify(root.profiles))
                        root.profiles = s.profiles ?? [];
                    root.subscription = s.subscription;
                    root.killswitch = s.killswitch ?? false;
                    root.blocking = s.blocking ?? false;
                } catch (e) {
                    console.warn("[vpn] bad state:", text);
                }
                root.polled = true;
            }
        }
    }

    // Steady poll; right after an operation (or while connecting) faster,
    // until the unit and the probe settle.
    Timer {
        running: true
        repeat: true
        triggeredOnStart: true
        interval: root.status === "connecting" || root.status === "disconnecting" || settle.running
            ? 1000 : (root.cfg.pollMs ?? 5000)
        onTriggered: root.refresh()
    }
    Timer {
        id: settle
        interval: 8000
    }
    Timer {
        id: stall
        interval: root.cfg.stallMs ?? 12000
        running: root.unit === "active" && !root.online && root.busy === "" && !root.stalled
        onTriggered: root.stalled = true
    }
    onOnlineChanged: if (root.online) root.stalled = false
    onUnitChanged: if (root.unit !== "active") root.stalled = false
    onStalledChanged: {
        if (!arm.armed)
            return;
        if (root.stalled)
            root.post("vpn:error", "accentRed", I18n.tr("VPN: no connection"));
        else if (root.online)
            root.events.cancel("vpn:error");
    }

    Process {
        id: pingProc
        command: [root.script, "ping"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/OK:(\d+)/);
                root.pingMs = m ? +m[1] : -2;
                root.pinging = false;
            }
        }
    }

    Process {
        id: speedProc
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

    onBlockingChanged: if (arm.armed && root.blocking)
        root.post("vpn:error", "accentRed", I18n.tr("VPN down · traffic blocked"))

    // Bar events: up / down (a real change after start-up), failures.
    readonly property bool up: root.unit === "active"
    onUpChanged: {
        if (!arm.armed || !(Config.data.events.vpn ?? true))
            return;
        root.events.cancel(root.up ? "vpn:off" : "vpn:on");
        root.post(root.up ? "vpn:on" : "vpn:off", root.up ? "qsBlue" : "islandFg",
            root.up ? (root.profile ? `VPN · ${root.profile}` : "VPN") : I18n.tr("VPN off"));
    }
    function post(key: string, color: string, text: string): void {
        if (!(Config.data.events.vpn ?? true))
            return;
        root.events.post({
            key,
            icon: root.up ? "" : "", // tabler shield-lock / shield
            color,
            text
        });
    }
    Timer {
        id: arm
        property bool armed: false
        running: true
        interval: Config.data.events.startupQuietMs
        onTriggered: armed = true
    }
}
