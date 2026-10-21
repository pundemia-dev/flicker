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
// polkit check, node switch / routing / subscription through pkexec (the
// shell's polkit agent asks; once `vpn.sh setup` ran, start / stop, node
// switch and a routing-only apply go without a password). Ping / speed test are separate and may run alongside.
// Kill switch (`vpn.sh killswitch`): an nftables block raised with sing-box
// that outlives a crash; only a stop (setActive(false) / release()) lowers it.
// Split routing (Config `vpn.routing`, the settings window) and the user's own
// sing-box JSON overlay (`vpn.sh edit`) take effect on applyRouting() (pkexec,
// sing-box restarts; a config it cannot start with is rolled back);
// `pending` = either differs from what is applied.
Scope {
    id: root
    required property var events
    // services/Polkit.qml: tells a dismissed prompt from a denial (pkexec 127).
    property var polkit: null

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
    // A config to switch nodes in / compose routing into (the selector's nodes).
    readonly property bool hasProfiles: root.profiles.length > 0
    property bool subscription: false
    // Kill switch on; blocking = its table is up while sing-box is not
    // (crashed / failed): no traffic until the VPN is back or released.
    property bool killswitch: false
    property bool blocking: false
    // The routing in force (as last applied) and whether the overlay file
    // changed since.
    property var appliedRouting: ({})
    property bool customPending: false
    readonly property var routing: Config.data.vpn?.routing ?? ({})
    readonly property bool routingPending: root.canon(root.routing) !== root.canon(root.appliedRouting)
    readonly property bool pending: root.installed && (root.routingPending || root.customPending)
    property bool polled: false

    // Running operation: "" | start | stop | restart | autostart | killswitch
    // | select | update | subscribe | routing.
    property string busy: ""
    property string selecting: ""
    property string error: ""
    // The operation `error` came from (a `busy` value).
    property string errorOp: ""
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
    // Routing + overlay into force; refresh = download the geosite / geoip
    // lists again even if fresh.
    function applyRouting(refresh: bool): void {
        if (root.installed && root.busy === "")
            root.run("routing", ["apply", JSON.stringify(root.routing)].concat(refresh ? ["refresh"] : []));
    }
    // The overlay (~/.config/flicker/vpn/custom.json) in an editor in the
    // user's terminal; applyRouting() puts it in force.
    function editConfig(): void {
        Quickshell.execDetached((Config.data.launcher?.apps?.terminal ?? ["kitty"]).concat([root.script, "edit"]));
    }
    // Key-order-free JSON, defaults filled in (routing comparison).
    function canon(r: var): string {
        const sort = v => Array.isArray(v) ? v.map(sort) : v && typeof v === "object"
            ? Object.keys(v).sort().reduce((o, k) => (o[k] = sort(v[k]), o), {}) : v;
        return JSON.stringify(sort({ final: r?.final ?? "proxy", rules: r?.rules ?? [] }));
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
        if (stateProc.running)
            return;
        stateProc.gen = root.opGen;
        stateProc.running = true;
    }

    function run(kind: string, args: var): void {
        root.busy = kind;
        root.error = "";
        op.dismissed = false;
        op.kind = kind;
        op.arg = args[1] ?? "";
        op.command = [root.script, ...args];
        op.running = true;
    }

    Process {
        id: op
        property string kind: ""
        property string arg: ""
        // Our polkit agent's prompt ended without success during it.
        property bool dismissed: false
        stdout: StdioCollector {
            id: opOut
        }
        onExited: code => {
            const err = opOut.text.split("\n").find(l => l.startsWith("ERR:"));
            // pkexec: 126 = the prompt was dismissed. 127 = not authorized,
            // which some agents also say for a dismissed prompt: a cancel when
            // ours saw its prompt end unsuccessfully, else (no agent, denied
            // outright) a failure. Without our agent it cannot tell: shown,
            // no toast.
            const ownAgent = root.polkit?.registered ?? false;
            const cancelled = !err && (code === 126 || code === 127 && op.dismissed);
            const unsure = !err && code === 127 && !ownAgent;
            // The error before `busy` clears: watchers of busy read it.
            if (code !== 0) {
                root.error = err ? err.substring(4) : cancelled ? "cancelled" : code === 127 ? "not authorized (polkit)" : `exit ${code}`;
                root.errorOp = op.kind;
            }
            root.busy = "";
            root.selecting = "";
            root.opGen++;
            if (code !== 0) {
                console.info("[vpn]", op.kind, "failed:", root.error);
                if (!cancelled && !unsure)
                    root.post("vpn:error", "accentRed", op.kind === "subscribe" || op.kind === "update"
                        ? I18n.tr("Subscription failed") : op.kind === "routing" ? I18n.tr("Routing failed") : I18n.tr("VPN failed"));
            } else if (op.kind === "subscribe" || op.kind === "update") {
                root.post("vpn:sub", "qsBlue", I18n.tr("Subscription updated"));
            } else if (op.kind === "routing") {
                root.post("vpn:sub", "qsBlue", I18n.tr("Routing applied"));
            } else if (op.kind === "select" && root.up) {
                root.events.cancel("vpn:off");
                root.post("vpn:on", "qsBlue", `VPN · ${op.arg}`);
            }
            root.stalled = false;
            root.refresh();
            settle.restart();
        }
    }

    Connections {
        target: root.polkit
        function onFinished(success: bool): void {
            if (op.running && !success)
                op.dismissed = true;
        }
    }

    // A root half is restarting the units itself (vpn.sh `state`): the unit
    // and the kill switch pass through states that are no real change.
    property bool restarting: false
    // Start / stop / restart too pass through "kill switch up, sing-box not"
    // (it is ordered before sing-box): no "traffic blocked" for those.
    readonly property bool holdBlocking: root.restarting || ["start", "stop", "restart"].includes(root.busy)
    // Bumped when an operation ends: a poll started before that is stale.
    property int opGen: 0

    Process {
        id: stateProc
        property int gen: 0
        command: [root.script, "state"]
        onExited: if (stateProc.gen !== root.opGen) Qt.callLater(root.refresh)
        stdout: StdioCollector {
            onStreamFinished: {
                if (stateProc.gen !== root.opGen)
                    return;
                try {
                    const s = JSON.parse(text);
                    root.installed = s.installed;
                    // The profile before the unit: onUpChanged names it.
                    root.profile = s.profile ?? "";
                    root.restarting = s.restarting ?? false;
                    if (!root.restarting)
                        root.unit = s.unit || "inactive";
                    root.enabled = s.enabled ?? false;
                    root.online = s.online;
                    if (JSON.stringify(s.profiles) !== JSON.stringify(root.profiles))
                        root.profiles = s.profiles ?? [];
                    root.subscription = s.subscription;
                    root.killswitch = s.killswitch ?? false;
                    if (!root.holdBlocking)
                        root.blocking = s.blocking ?? false;
                    if (root.canon(s.routing) !== root.canon(root.appliedRouting))
                        root.appliedRouting = s.routing ?? {};
                    root.customPending = s.customPending ?? false;
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
