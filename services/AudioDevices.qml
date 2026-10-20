import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../config"
import "AudioGraph.js" as AudioGraph

// Audio devices as the user sees them (one row per physical device, see
// AudioGraph.js) + the actions on them. Shared by the QS audio panel, the
// settings window's Sound section and AudioPolicy. Binds every node (their
// properties read {} until bound); PipeWire nodes / link groups come from
// Quickshell, ports / cards / profiles from pactl JSON (Quickshell has no
// card API), re-read on card events, sink / source add / remove and default
// changes (not on every volume change).
// Known devices (Quickshell.statePath("audio-devices.json")): every device
// ever seen, per direction, in the user's PRIORITY order — the settings
// list, the fallback when the current device goes away (AudioPolicy).
Scope {
    id: root

    readonly property var cfg: Config.data.audio
    readonly property var nodeList: Pipewire.nodes.values
    PwObjectTracker {
        objects: root.nodeList
    }

    // Snapshots (plain objects), rebuilt on any node / link / pactl change.
    property var nodes: []
    property var groups: []
    property var pulse: ({ sinks: [], sources: [], cards: [] })
    readonly property int defaultSink: Pipewire.defaultAudioSink?.id ?? -1
    readonly property int defaultSource: Pipewire.defaultAudioSource?.id ?? -1
    readonly property var outputs: AudioGraph.devices(root.nodes, root.groups, root.pulse, root.defaultSink, true, root.cfg, root.keysOf(root.known.outputs), false)
    readonly property var inputs: AudioGraph.devices(root.nodes, root.groups, root.pulse, root.defaultSource, false, root.cfg, root.keysOf(root.known.inputs), false)
    // With hidden ones (settings).
    readonly property var allOutputs: AudioGraph.devices(root.nodes, root.groups, root.pulse, root.defaultSink, true, root.cfg, root.keysOf(root.known.outputs), true)
    readonly property var allInputs: AudioGraph.devices(root.nodes, root.groups, root.pulse, root.defaultSource, false, root.cfg, root.keysOf(root.known.inputs), true)
    readonly property var streams: AudioGraph.streams(root.nodes, root.groups)
        .map(s => Object.assign({ targetKey: AudioGraph.rowOfNode(root.outputs, root.nodes, root.groups, s.target, true) }, s))
    readonly property var currentOutput: root.outputs.find(r => r.isDefault) ?? null
    readonly property var currentInput: root.inputs.find(r => r.isDefault) ?? null

    function keysOf(list: var): var {
        return (list ?? []).map(k => k.key);
    }

    function node(id: int): var {
        return root.nodeList.find(n => n.id === id) ?? null;
    }
    function nodeByName(name: string): var {
        return root.nodeList.find(n => n.name === name) ?? null;
    }

    function snapshot(): void {
        root.nodes = root.nodeList.map(n => {
            const p = n.properties ?? {};
            return {
                id: n.id,
                name: n.name ?? "",
                desc: n.description ?? "",
                nick: n.nickname ?? "",
                cls: p["media.class"] ?? "",
                lg: p["node.link-group"] ?? "",
                devId: p["device.id"],
                api: p["device.api"] ?? "",
                bus: p["device.bus"] ?? "",
                icon: p["device.icon_name"] ?? p["device.icon-name"] ?? "",
                form: p["device.form-factor"] ?? p["device.form_factor"] ?? "",
                address: p["api.bluez5.address"] ?? "",
                props: p
            };
        });
        root.groups = (Pipewire.linkGroups.values ?? []).map(g => ({ src: g.source?.id ?? -1, dst: g.target?.id ?? -1 }));
    }
    Timer {
        id: settle
        interval: 60
        onTriggered: root.snapshot()
    }
    Component.onCompleted: {
        root.snapshot();
        pactlQuery.running = true;
    }
    Connections {
        target: Pipewire.nodes
        function onValuesChanged(): void {
            settle.restart();
            pactlSettle.restart();
        }
    }
    Connections {
        target: Pipewire.linkGroups
        function onValuesChanged(): void { settle.restart(); }
    }
    // Properties arrive once a node is bound (after the tracker took it).
    Instantiator {
        model: root.nodeList
        delegate: Connections {
            required property var modelData
            target: modelData
            function onReadyChanged(): void { settle.restart(); }
            function onPropertiesChanged(): void { settle.restart(); }
        }
    }

    // pactl: one JSON object of the three lists.
    Process {
        id: pactlQuery
        command: ["sh", "-c", "printf '{\"sinks\":'; pactl -f json list sinks; printf ',\"sources\":'; pactl -f json list sources; printf ',\"cards\":'; pactl -f json list cards; printf '}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.pulse = JSON.parse(this.text);
                } catch (e) {
                    console.warn("AudioDevices: pactl JSON:", e);
                }
            }
        }
    }
    Timer {
        id: pactlSettle
        interval: 150
        onTriggered: {
            if (pactlQuery.running)
                pactlSettle.restart();
            else
                pactlQuery.running = true;
        }
    }
    Process {
        id: watch
        running: true
        command: ["pactl", "subscribe"]
        stdout: SplitParser {
            onRead: line => {
                if (/on card /.test(line) || /'(new|remove)' on (sink|source) /.test(line) || /on server/.test(line))
                    pactlSettle.restart();
            }
        }
        // pipewire-pulse restarted: subscribe again after a moment.
        onExited: respawn.restart()
    }
    Timer {
        id: respawn
        interval: 3000
        onTriggered: {
            watch.running = true;
            pactlSettle.restart();
        }
    }

    // ---- known devices (priority order) ----

    property var known: ({ outputs: [], inputs: [] })
    // Nothing is learned before the file was read (or found missing).
    property bool knownReady: false
    FileView {
        id: knownFile
        path: Quickshell.statePath("audio-devices.json")
        printErrors: false
        watchChanges: true
        onFileChanged: knownFile.reload()
        onLoaded: {
            try {
                const d = JSON.parse(knownFile.text());
                root.known = { outputs: d.outputs ?? [], inputs: d.inputs ?? [] };
            } catch (e) {
                root.known = { outputs: [], inputs: [] };
            }
            root.knownReady = true;
            root.learn();
        }
        onLoadFailed: {
            root.knownReady = true;
            root.learn();
        }
    }
    Timer {
        id: saveKnown
        interval: 500
        onTriggered: knownFile.setText(JSON.stringify(root.known, null, 2))
    }
    // Deferred: `known` feeds the rows' order (a binding loop otherwise).
    onOutputsChanged: { Qt.callLater(root.learn); Qt.callLater(root.claimPending); }
    onInputsChanged: { Qt.callLater(root.learn); Qt.callLater(root.claimPending); }

    // New real devices join the end of their list; a label change (rename,
    // Bluetooth alias) is kept for when the device is away.
    function learn(): void {
        if (!root.knownReady)
            return;
        let changed = false;
        const next = { outputs: root.known.outputs.slice(), inputs: root.known.inputs.slice() };
        for (const [list, rows] of [[next.outputs, root.allOutputs], [next.inputs, root.allInputs]]) {
            for (const r of rows) {
                if (r.nodeId < 0 || !r.resolved)
                    continue;
                const i = list.findIndex(k => k.key === r.key);
                const entry = { key: r.key, label: r.label, translate: r.translate, kind: r.kind };
                if (i < 0) {
                    list.push(entry);
                    changed = true;
                } else if (list[i].label !== r.label || list[i].kind !== r.kind) {
                    list[i] = entry;
                    changed = true;
                }
            }
        }
        if (changed) {
            root.known = next;
            saveKnown.restart();
        }
    }

    function moveKnown(sink: bool, key: string, dir: int): void {
        const list = (sink ? root.known.outputs : root.known.inputs).slice();
        const i = list.findIndex(k => k.key === key), j = i + dir;
        if (i < 0 || j < 0 || j >= list.length)
            return;
        [list[i], list[j]] = [list[j], list[i]];
        root.known = sink ? { outputs: list, inputs: root.known.inputs } : { outputs: root.known.outputs, inputs: list };
        saveKnown.restart();
    }
    function forgetKnown(sink: bool, key: string): void {
        const list = (sink ? root.known.outputs : root.known.inputs).filter(k => k.key !== key);
        root.known = sink ? { outputs: list, inputs: root.known.inputs } : { outputs: root.known.outputs, inputs: list };
        saveKnown.restart();
    }

    // ---- actions ----

    // A switch that only creates its node later (card profile / port): make
    // that node the default once it shows up (within a few seconds).
    property var pending: null
    Timer {
        id: pendingTimeout
        interval: 5000
        onTriggered: root.pending = null
    }
    function claimPending(): void {
        const p = root.pending;
        if (!p)
            return;
        const rows = p.sink ? root.outputs : root.inputs;
        const hit = rows.find(r => r.nodeId >= 0 && (p.card ? r.bt?.card === p.card : r.kind === p.kind));
        if (!hit)
            return;
        root.pending = null;
        root.makeDefault(hit.nodeId, p.sink);
    }

    function makeDefault(nodeId: int, sink: bool): void {
        const n = root.node(nodeId);
        if (!n)
            return;
        if (sink)
            Pipewire.preferredDefaultAudioSink = n;
        else
            Pipewire.preferredDefaultAudioSource = n;
    }

    // Row → the current device (port / profile switch when it has no node).
    function choose(row: var, sink: bool): void {
        const a = row?.action ?? {};
        if (!row?.available)
            return;
        if (a.type === "node")
            root.makeDefault(a.nodeId, sink);
        else if (a.type === "port") {
            const kind = sink ? "sink" : "source";
            root.run(["sh", "-c", `pactl set-${kind}-port "$1" "$2" && pactl set-default-${kind} "$1"`, "sh", a.target, a.port]);
        } else if (a.type === "profile") {
            root.pending = { sink: sink, card: row.bt ? a.card : "", kind: row.kind };
            pendingTimeout.restart();
            root.run(["pactl", "set-card-profile", a.card, a.profile]);
        }
    }

    // Bluetooth: { music, calls, active } or null (see AudioGraph.btModes).
    function btModes(card: string): var {
        return AudioGraph.btModes(root.pulse.cards, card);
    }
    function profiles(card: string): var {
        return AudioGraph.profiles(root.pulse.cards, card);
    }
    function setProfile(card: string, profile: string): void {
        root.run(["pactl", "set-card-profile", card, profile]);
    }
    function latencyMs(card: string, port: string): int {
        return AudioGraph.latencyMs(root.pulse.cards, card, port);
    }
    function setLatency(card: string, port: string, ms: int): void {
        root.run(["pactl", "set-port-latency-offset", card, port, `${Math.round(ms * 1000)}`]);
    }

    // pipewire-pulse indexes sink inputs by object.serial, not the node id.
    function moveStream(serial: string, rowKey: string): void {
        const row = root.outputs.find(r => r.key === rowKey);
        const n = row && row.nodeId >= 0 ? root.node(row.nodeId) : null;
        if (serial !== "" && n)
            root.run(["pactl", "move-sink-input", serial, n.name]);
    }

    function run(cmd: var): void {
        Quickshell.execDetached(cmd);
        pactlSettle.restart();
    }
}
