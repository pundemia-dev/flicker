import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../config"
import "AudioGraph.js" as AudioGraph

// Audio behaviour the user sets in settings → Sound (Config.audio), on top
// of services/AudioDevices:
//   autoSwitch      a NEW device (or plugged headphones): "always" make it
//                   current, "ask" (an event; tap = switch), "never" (a
//                   switch WirePlumber made to it is undone)
//   followPriority  the current device went away: the first present one in
//                   the user's order (AudioDevices.known), not WirePlumber's
//   btReturnToMusic a Bluetooth headset left in call mode goes back to music
//                   once the app recording from it stops (btReturnDelayMs)
//   balance         { deviceKey: -1..1 } kept on the current output's
//                   channel volumes (a volume change from keys / Quick
//                   Settings sets every channel alike — undone here)
//   voice           { enabled, gainControl }: WebRTC noise / echo
//                   suppression (scripts/audio/audio.sh voice) on the chosen
//                   mic; its source "flicker_voice" is made current, choosing
//                   another mic re-targets it
// Also session tools: listen to yourself (mic → output loopback, only on
// headphone-like outputs), the channel test, WirePlumber settings
// (`wpctl settings`), the per-app outputs WirePlumber remembers.
Scope {
    id: root
    required property var devices
    required property var audio
    required property var events

    readonly property var cfg: Config.data.audio
    readonly property string script: Quickshell.shellDir + "/scripts/audio/audio.sh"

    // Start-up: devices appear, WirePlumber restores defaults — no policy.
    property bool armed: false
    Timer {
        running: true
        interval: Math.max(3000, Config.data.events?.startupQuietMs ?? 3000)
        onTriggered: {
            root.prevOutputs = root.devices.outputs;
            root.prevInputs = root.devices.inputs;
            root.armed = true;
        }
    }

    // ---- new devices / gone devices ----

    // Rows at the last review ("never" reverts to their current one).
    property var prevOutputs: []
    property var prevInputs: []

    Connections {
        target: root.devices
        function onOutputsChanged(): void { changes.restart(); }
        function onInputsChanged(): void { changes.restart(); }
    }
    // Settled view of a burst (a device brings its sink, source and card).
    Timer {
        id: changes
        interval: 400
        onTriggered: root.review()
    }

    // Appeared or got plugged in. A Bluetooth headset's "switch to calls"
    // microphone row is an offer, not a device; one coming back from its own
    // profile switch is not new either (AudioDevices.pending claims it).
    function fresh(now: var, before: var): var {
        return now.filter(r => r.available && r.sub !== "callMode" && !root.devices.isSwitching(r, true)
            && !before.some(p => p.key === r.key && p.available));
    }
    function revert(before: var, sink: bool): void {
        const was = before.find(p => p.isDefault && p.nodeId >= 0);
        if (was)
            root.devices.makeDefault(was.nodeId, sink);
    }

    function review(): void {
        if (!root.armed)
            return;
        const outs = root.devices.outputs, ins = root.devices.inputs;
        const newOut = root.fresh(outs, root.prevOutputs);
        const newIn = root.fresh(ins, root.prevInputs);
        // A headset mid profile switch is only away for a moment (its
        // microphone really goes when it switches back to music).
        const lostOut = root.prevOutputs.some(p => p.isDefault && !outs.some(r => r.key === p.key) && !root.devices.isSwitching(p, true));
        const lostIn = root.prevInputs.some(p => p.isDefault && !ins.some(r => r.key === p.key) && !root.devices.isSwitching(p, false));
        const mode = root.cfg.autoSwitch ?? "always";
        if (newOut.length > 0 || newIn.length > 0) {
            if (mode === "always") {
                if (newOut.length > 0)
                    root.devices.choose(newOut[0], true);
                if (newIn.length > 0)
                    root.devices.choose(newIn[0], false);
            } else if (mode === "ask" && newOut.length > 0 && !newOut[0].isDefault) {
                root.ask(newOut[0], newIn);
            } else if (mode === "never") {
                if (newOut.some(r => r.isDefault))
                    root.revert(root.prevOutputs, true);
                if (newIn.some(r => r.isDefault))
                    root.revert(root.prevInputs, false);
            }
        }
        // The current device went away: the user's order decides.
        if ((root.cfg.followPriority ?? true) && newOut.length === 0 && lostOut) {
            const next = outs.find(r => r.available && r.nodeId >= 0);
            if (next && !next.isDefault)
                root.devices.makeDefault(next.nodeId, true);
        }
        if ((root.cfg.followPriority ?? true) && newIn.length === 0 && lostIn) {
            const next = ins.find(r => r.available && r.nodeId >= 0 && r.key !== root.voiceKey);
            if (next && !next.isDefault)
                root.devices.makeDefault(next.nodeId, false);
        }
        root.prevOutputs = outs;
        root.prevInputs = ins;
    }

    function ask(row: var, inputs: var): void {
        const sameDevice = inputs.find(r => (row.bt && r.bt?.address === row.bt.address) || (row.card !== "" && r.card === row.card));
        root.events?.post({
            key: "audioAsk",
            glyph: AudioGraph.isPersonal(row.kind) ? "headphones" : row.kind === "hdmi" ? "display" : "speaker",
            icon: "",
            color: "qsBlue",
            texts: [row.translate ? I18n.tr(row.label) : row.label, I18n.tr("Tap to switch")],
            tap: () => {
                root.devices.choose(row, true);
                if (sameDevice)
                    root.devices.choose(sameDevice, false);
            }
        });
    }

    // ---- Bluetooth back to music after a call ----

    // card → true once something recorded from its microphone.
    property var hadCall: ({})
    Timer {
        interval: 2000
        repeat: true
        running: root.cfg.btReturnToMusic ?? true
        onTriggered: root.checkCalls()
    }
    property var idleSince: ({})
    function checkCalls(): void {
        const nodes = root.devices.nodes, groups = root.devices.groups;
        const now = Date.now();
        const had = Object.assign({}, root.hadCall), idle = Object.assign({}, root.idleSince);
        for (const c of root.devices.pulse.cards ?? []) {
            if (!(c.name ?? "").startsWith("bluez_") || !AudioGraph.isCall(c.active_profile)) {
                delete had[c.name];
                delete idle[c.name];
                continue;
            }
            const addr = `${c.properties?.["api.bluez5.address"] ?? ""}`.toUpperCase();
            // A pinned Calls stays (AudioBtModes).
            if (root.devices.btPins.pinOf(addr) !== "") {
                delete had[c.name];
                delete idle[c.name];
                continue;
            }
            const mic = nodes.find(n => n.cls === "Audio/Source" && `${n.address}`.toUpperCase() === addr);
            const recording = !!mic && groups.some(g => {
                if (g.src !== mic.id)
                    return false;
                const dst = nodes.find(n => n.id === g.dst);
                return dst && (dst.cls ?? "").startsWith("Stream/Input") && !/^(quickshell|flicker_)/.test(dst.name ?? "");
            });
            if (recording) {
                had[c.name] = true;
                delete idle[c.name];
            } else if (had[c.name]) {
                idle[c.name] = idle[c.name] ?? now;
                if (now - idle[c.name] >= (root.cfg.btReturnDelayMs ?? 5000)) {
                    const music = AudioGraph.bestProfile(c, AudioGraph.isA2dp);
                    if (music)
                        root.devices.setProfile(c.name, music);
                    delete had[c.name];
                    delete idle[c.name];
                }
            }
        }
        root.hadCall = had;
        root.idleSince = idle;
    }

    // ---- balance ----

    readonly property var sinkNode: Pipewire.defaultAudioSink
    readonly property var balanceMap: root.cfg.balance ?? ({})
    readonly property string outputKey: root.devices.currentOutput?.key ?? ""
    readonly property bool hasBalance: root.outputKey !== "" && root.balanceMap[root.outputKey] !== undefined
    readonly property real balance: root.hasBalance ? Number(root.balanceMap[root.outputKey]) : 0
    Connections {
        target: root.sinkNode?.audio ?? null
        function onVolumesChanged(): void { Qt.callLater(root.applyBalance); }
        function onChannelsChanged(): void { Qt.callLater(root.applyBalance); }
    }
    onBalanceChanged: Qt.callLater(root.applyBalance)
    onOutputKeyChanged: Qt.callLater(root.applyBalance)

    function side(ch: int): int {
        const left = [PwAudioChannel.FrontLeft, PwAudioChannel.SideLeft, PwAudioChannel.RearLeft,
            PwAudioChannel.FrontLeftCenter, PwAudioChannel.RearLeftCenter, PwAudioChannel.FrontLeftWide];
        const right = [PwAudioChannel.FrontRight, PwAudioChannel.SideRight, PwAudioChannel.RearRight,
            PwAudioChannel.FrontRightCenter, PwAudioChannel.RearRightCenter, PwAudioChannel.FrontRightWide];
        return left.includes(ch) ? -1 : right.includes(ch) ? 1 : 0;
    }
    // Can the current output be balanced (has left and right channels)?
    readonly property bool balanceable: {
        const ch = root.sinkNode?.audio?.channels ?? [];
        return ch.some(c => root.side(c) < 0) && ch.some(c => root.side(c) > 0);
    }
    function applyBalance(): void {
        const a = root.sinkNode?.audio;
        if (!root.hasBalance || !a || !root.sinkNode.ready || !root.balanceable)
            return;
        const vols = a.volumes ?? [], chans = a.channels ?? [];
        const top = Math.max(...vols, 0);
        const b = Math.max(-1, Math.min(1, root.balance));
        const want = chans.map(c => {
            const s = root.side(c);
            return top * (s < 0 ? Math.min(1, 1 - b) : s > 0 ? Math.min(1, 1 + b) : 1);
        });
        if (want.some((v, i) => Math.abs(v - (vols[i] ?? 0)) > 0.002))
            a.volumes = want;
    }
    function setBalance(key: string, value: real): void {
        const map = Object.assign({}, root.balanceMap);
        map[key] = Math.round(value * 100) / 100;
        Config.set("audio.balance", map);
    }

    // ---- headphone volume cap (Audio.maxVolume) ----

    Binding {
        target: root.audio
        property: "personalOutput"
        value: AudioGraph.isPersonal(root.devices.currentOutput?.kind ?? "")
    }

    // ---- voice processing ----

    readonly property bool voiceOn: root.cfg.voice?.enabled ?? false
    readonly property bool voiceAgc: root.cfg.voice?.gainControl ?? false
    // The mic it processes (node name) and that mic's row key.
    property string voiceTarget: ""
    readonly property string voiceKey: root.devices.inputs.find(r => r.members.some(m => m.name === "flicker_voice"))?.key ?? ""
    readonly property var voiceNode: root.devices.nodeList.find(n => n.name === "flicker_voice") ?? null
    readonly property var sourceNode: Pipewire.defaultAudioSource

    // A crash loop (5 exits within 3 s of starting) gives up until the
    // setting or the mic changes.
    property int voiceFails: 0
    property real voiceStarted: 0
    Process {
        id: voiceProc
        command: ["sh", root.script, "voice", root.voiceTarget, root.voiceAgc ? "1" : "0"]
        onStarted: root.voiceStarted = Date.now()
        onExited: (code, status) => {
            root.voiceFails = Date.now() - root.voiceStarted < 3000 ? root.voiceFails + 1 : 0;
            if (root.voiceFails >= 5)
                console.warn("AudioPolicy: voice processing keeps exiting, giving up");
            else if (root.voiceOn && root.voiceTarget !== "" && !voiceRestart.running)
                voiceRestart.restart();
        }
    }
    // Crash / restart pacing (also a target change: stop, then start).
    Timer {
        id: voiceRestart
        interval: 600
        onTriggered: {
            if (root.voiceOn && root.voiceTarget !== "")
                voiceProc.running = true;
        }
    }
    function retargetVoice(): void {
        if (!root.voiceOn) {
            if (voiceProc.running) {
                // Back to the real mic before its stand-in goes.
                const real = root.devices.nodeByName(root.voiceTarget);
                if (real && root.sourceNode?.name === "flicker_voice")
                    Pipewire.preferredDefaultAudioSource = real;
                voiceProc.running = false;
            }
            return;
        }
        const src = root.sourceNode;
        if (src && src.name !== "flicker_voice" && !(src.name ?? "").startsWith("flicker_") && src.name !== root.voiceTarget) {
            root.voiceTarget = src.name;
            root.voiceFails = 0;
            if (voiceProc.running)
                voiceProc.running = false;
            voiceRestart.restart();
        } else if (root.voiceTarget !== "" && !voiceProc.running && !voiceRestart.running) {
            voiceRestart.restart();
        }
    }
    onVoiceOnChanged: {
        root.voiceFails = 0;
        root.retargetVoice();
    }
    onVoiceAgcChanged: if (voiceProc.running) { voiceProc.running = false; voiceRestart.restart(); }
    onSourceNodeChanged: Qt.callLater(root.retargetVoice)
    Component.onCompleted: Qt.callLater(root.retargetVoice)
    // The cleaned source appeared: it becomes the current mic.
    onVoiceNodeChanged: {
        if (root.voiceOn && root.voiceNode && root.sourceNode !== root.voiceNode)
            Pipewire.preferredDefaultAudioSource = root.voiceNode;
    }

    // ---- listen to yourself ----

    property bool listening: false
    readonly property bool canListen: AudioGraph.isPersonal(root.devices.currentOutput?.kind ?? "")
    // Never into speakers (feedback): stops when the output changes to one.
    onCanListenChanged: if (!root.canListen) root.listening = false
    Process {
        running: root.listening && root.canListen
        command: ["pw-loopback", "-n", "flicker_listen", "-c", "1", "-m", "[ MONO ]",
            "--capture-props", "{ node.name = flicker_listen.capture }",
            "--playback-props", "{ node.name = flicker_listen.playback media.role = Test }"]
        onExited: root.listening = false
    }

    // ---- channel test ----

    function testChannel(nodeId: int, side: string): void {
        const n = root.devices.node(nodeId);
        if (n)
            Quickshell.execDetached(["sh", root.script, "test", n.name, side]);
    }

    // ---- WirePlumber settings (wpctl settings) ----

    property var wp: ({})
    function refreshWp(): void {
        if (!wpQuery.running)
            wpQuery.running = true;
    }
    Process {
        id: wpQuery
        command: ["wpctl", "settings"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = {};
                let id = "";
                for (const line of this.text.split("\n")) {
                    const m = /^\s*- Id:\s*(\S+)/.exec(line);
                    if (m) {
                        id = m[1];
                        continue;
                    }
                    const v = /^\s*Value:\s*(.*)$/.exec(line);
                    if (v && id) {
                        const raw = v[1].trim();
                        out[id] = raw === "true" ? true : raw === "false" ? false : raw.replace(/^"(.*)"$/, "$1");
                        id = "";
                    }
                }
                // Held off by a pinned headset: settings show the user's value.
                const pins = root.devices.btPins;
                if (pins.holding && root.wp[pins.wpKey] !== undefined)
                    out[pins.wpKey] = root.wp[pins.wpKey];
                root.wp = out;
            }
        }
    }
    function setWp(key: string, value: var): void {
        const next = Object.assign({}, root.wp);
        next[key] = value;
        root.wp = next;
        wpSet.command = ["wpctl", "settings", "--save", key, typeof value === "string" ? JSON.stringify(value) : `${value}`];
        wpSet.running = true;
    }
    Process {
        id: wpSet
        onExited: {
            // --save also set the runtime value: a pinned headset holds it off again.
            root.devices.btPins.reassert();
            root.refreshWp();
        }
    }

    // ---- per-app outputs WirePlumber remembers ----

    // [{ key, kind ("application.name" …), app, target }]: entries of its
    // stream-properties state with a "target".
    property var routes: []
    FileView {
        id: routeFile
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/wireplumber/stream-properties"
        watchChanges: true
        printErrors: false
        onFileChanged: routeFile.reload()
        onLoaded: {
            const list = [];
            for (const line of routeFile.text().split("\n")) {
                const eq = line.indexOf("=");
                if (eq < 0 || !line.startsWith("Output/Audio:"))
                    continue;
                let data = null;
                try {
                    data = JSON.parse(line.slice(eq + 1));
                } catch (e) {
                    continue;
                }
                if (!data?.target)
                    continue;
                const key = line.slice(0, eq);
                const parts = key.split(":");
                list.push({ key: key, kind: parts[1] ?? "", app: parts.slice(2).join(":").replace(/\\s/g, " "), target: data.target });
            }
            root.routes = list;
        }
    }
    function forgetRoutes(keys: var): void {
        Quickshell.execDetached(["python3", Quickshell.shellDir + "/scripts/audio/forget-routes.py", ...keys]);
    }
}
