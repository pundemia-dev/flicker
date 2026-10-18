import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// LocalSend (pShell stash port), both directions.
// Outbound: `start(files)` → discover peers (scripts/localsend/discover.py,
// one `alias\tip\tdeviceType\tdeviceModel` line per device → roles
// name/ip/kind/os) → `sendTo(ip)`
// uploads every pending file in ONE session (send.py). phase:
// idle | scanning | ready | sending.
// Inbound: while `receiving` the receive server (receive.py) announces
// `alias` on the LAN; its JSON-lines events drive `request` (accept/reject
// card in the stash module) and decisions go back over stdin. Accepted files
// are mirrored into the stash dir.
Scope {
    id: root
    required property var cfg
    // Stash dir the receive server mirrors accepted files into.
    property string stashDir: ""

    readonly property string scriptsDir: `${Quickshell.shellDir}/scripts/localsend`
    readonly property bool enabled: root.cfg?.localsend ?? true

    // ── Outbound ──
    property string phase: "idle"
    property var pendingFiles: []
    readonly property alias devices: deviceModel
    readonly property bool busy: root.phase !== "idle"

    // false = not started (disabled / nothing to send / an upload runs).
    function start(files: var): bool {
        if (!root.enabled || !files || files.length === 0)
            return false;
        if (root.phase === "sending") {
            Quickshell.execDetached(["notify-send", "-a", "Flicker", "LocalSend", I18n.tr("Wait for the current transfer to finish")]);
            return false;
        }
        root.pendingFiles = files;
        // A scan in flight serves the new files too (devices do not depend
        // on them).
        if (root.phase !== "scanning")
            root.rescan();
        return true;
    }

    // Restarting a still-running Process in the same tick is a no-op (the
    // killed run's partial output would land as the result), so a scan
    // that is still alive is killed and the new one starts from onExited.
    property bool rescanQueued: false
    // The killed run still delivers its (partial) stdout once: skip it.
    property bool scanKilled: false
    function rescan(): void {
        if (root.phase === "sending")
            return;
        deviceModel.clear();
        root.phase = "scanning";
        if (discover.running) {
            root.rescanQueued = true;
            root.scanKilled = true;
            discover.running = false;
        } else {
            discover.running = true;
        }
    }

    function sendTo(ip: string): void {
        if (root.pendingFiles.length === 0 || root.phase === "sending")
            return;
        root.phase = "sending";
        sender.command = ["python3", `${root.scriptsDir}/send.py`, ip].concat(root.pendingFiles);
        sender.running = true;
    }

    // Picker dismissed before a target was chosen. A running upload is left
    // alone: it reports through notify-send when it finishes.
    function cancel(): void {
        if (root.phase === "sending")
            return;
        root.rescanQueued = false;
        if (discover.running)
            root.scanKilled = true;
        discover.running = false;
        root.phase = "idle";
        root.pendingFiles = [];
    }

    signal sendFinished(bool ok)

    ListModel {
        id: deviceModel
    }

    Process {
        id: discover
        command: ["python3", `${root.scriptsDir}/discover.py`]
        onExited: {
            if (root.rescanQueued) {
                root.rescanQueued = false;
                discover.running = true;
            }
        }
        stdout: StdioCollector {
            id: discoverOut
            onStreamFinished: {
                if (root.scanKilled) {
                    root.scanKilled = false;
                    return;
                }
                if (root.phase !== "scanning")
                    return;
                deviceModel.clear();
                for (const line of discoverOut.text.trim().split("\n")) {
                    const p = line.split("\t");
                    const ip = (p[1] ?? "").trim();
                    if (!/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(ip))
                        continue;
                    deviceModel.append({
                        name: p[0].trim(),
                        ip: ip,
                        kind: (p[2] ?? "").trim(),
                        os: (p[3] ?? "").trim()
                    });
                }
                root.phase = "ready";
            }
        }
    }

    Process {
        id: sender
        stderr: SplitParser {
            onRead: line => console.log("[localsend-send]", line)
        }
        onExited: code => {
            root.phase = "idle";
            root.pendingFiles = [];
            root.sendFinished(code === 0);
        }
    }

    // ── Inbound ──
    // Session toggle (stash tray antenna button); `receive` in config is
    // the startup default. Not written back: config.json is hand-edited.
    property bool receiving: root.enabled && (root.cfg?.receive ?? false)
    // The tray toggle breaks the binding: a config change (settings window)
    // still switches it.
    readonly property bool receiveWanted: root.enabled && (root.cfg?.receive ?? false)
    onReceiveWantedChanged: root.receiving = root.receiveWanted
    readonly property string deviceName: root.cfg?.alias ?? "Flicker Stash"
    // A new name reaches a running receiver only through a restart: stop
    // it, onExited starts it again with the new --alias.
    property bool renaming: false
    onDeviceNameChanged: if (server.running) root.renaming = true
    property bool serverReady: false
    // Request awaiting a decision OR mid-transfer (null when idle).
    // { sessionId, alias, files:[{id,name,size,type}], totalSize, isText?, text? }
    property var request: null
    readonly property bool hasIncoming: root.request !== null
    property bool transferring: false
    property real receivedBytes: 0
    property real totalBytes: 0
    readonly property real progress: root.totalBytes > 0 ? Math.min(1, root.receivedBytes / root.totalBytes) : 0
    property var queue: []

    signal requestArrived
    signal fileReceived(string path)

    function accept(dir: string): void {
        if (!root.request)
            return;
        root.transferring = true;
        root.receivedBytes = 0;
        root.totalBytes = root.request.totalSize ?? 0;
        root.write({ action: "accept", sessionId: root.request.sessionId, dir: dir });
    }

    function reject(): void {
        if (!root.request)
            return;
        root.write({ action: "reject", sessionId: root.request.sessionId });
        root.advance();
    }

    function write(obj: var): void {
        if (server.running)
            server.write(JSON.stringify(obj) + "\n");
    }

    function advance(): void {
        root.transferring = false;
        root.receivedBytes = 0;
        root.totalBytes = 0;
        if (root.queue.length > 0) {
            root.request = root.queue[0];
            root.queue = root.queue.slice(1);
            root.requestArrived();
        } else {
            root.request = null;
        }
    }

    function onEvent(line: string): void {
        let ev;
        try {
            ev = JSON.parse(line);
        } catch (e) {
            return;
        }
        const own = root.request && ev.sessionId === root.request.sessionId;
        switch (ev.event) {
        case "ready":
            root.serverReady = true;
            break;
        case "request":
            if (root.request === null) {
                root.request = ev;
                root.requestArrived();
            } else {
                root.queue = root.queue.concat([ev]);
            }
            break;
        case "progress":
            if (own) {
                root.receivedBytes = ev.received;
                root.totalBytes = ev.total;
            }
            break;
        case "file-done":
            if (ev.path)
                root.fileReceived(ev.path);
            break;
        case "session-done":
            if (own)
                root.advance();
            break;
        case "cancelled":
        case "timeout":
        case "session-failed":
            // Sender went away / declined / stalled: never leave the card up.
            if (own)
                root.advance();
            else
                root.queue = root.queue.filter(r => r.sessionId !== ev.sessionId);
            break;
        }
    }

    onReceivingChanged: {
        if (root.receiving)
            return;
        root.serverReady = false;
        root.transferring = false;
        root.request = null;
        root.queue = [];
    }

    Process {
        id: server
        running: root.receiving && !root.renaming
        command: ["python3", `${root.scriptsDir}/receive.py`, "--alias", root.deviceName, "--stash-dir", root.stashDir]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => root.onEvent(line)
        }
        stderr: SplitParser {
            onRead: line => console.log("[localsend-recv]", line)
        }
        // Died on its own (port 53317 busy — e.g. pShell's receiver — or a
        // crash): switch the toggle off instead of showing a dead server on.
        onExited: code => {
            if (root.renaming) {
                root.renaming = false;
                return;
            }
            if (!root.receiving)
                return;
            console.warn("[LocalSend] receive server exited:", code);
            Quickshell.execDetached(["notify-send", "-a", "Flicker", "LocalSend", I18n.tr("Receiving failed to start (port 53317 busy?)")]);
            root.receiving = false;
        }
    }
}
