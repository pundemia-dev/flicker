import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../config"

// Privacy dot source (iOS): ONE dot, the most sensitive capture wins —
// screen share (red) > camera (green) > microphone (orange).
//   screen: a PipeWire Video/Source that is not a camera = a screencast
//           stream (xdpw "xdpw-stream", niri's own cast, cosmic, ...).
//           wf-recorder (our recording) uses screencopy, not PipeWire, and
//           has its own red clock plate anyway.
//   camera: a PipeWire camera node with a consumer linked to it, or any
//           process holding /dev/video* (browsers open V4L2 directly);
//           PipeWire's own handle on the device is ignored.
//   mic:    Audio.micActive (own capture streams already filtered there).
// Untracked PipeWire nodes have EMPTY `properties`, so names/kinds come
// from node.name + node.type; consumers are tracked to read their app name.
Scope {
    id: root
    required property var audio

    readonly property var cfg: Config.data.privacy

    readonly property string kind: root.screenNodes.length > 0 ? "screen"
        : (root.cameraActive ? "camera" : (root.audio.micActive ? "mic" : ""))
    readonly property bool active: root.kind !== ""
    readonly property string appName: root.kind === "screen" ? root.consumerName(root.screenNodes, I18n.tr("Screen"))
        : root.kind === "camera" ? (root.cameraProcs[0] ?? root.consumerName(root.cameraNodes, I18n.tr("Camera")))
        : root.kind === "mic" ? root.audio.micAppName : ""

    function isVideoSource(n: var): bool {
        return n && !n.isStream && (n.type & PwNodeType.VideoSource) === PwNodeType.VideoSource;
    }
    function isCamera(n: var): bool {
        const name = `${n.name ?? ""}`;
        return (root.cfg.cameraPrefixes ?? []).some(p => name.startsWith(p));
    }
    function excluded(n: var): bool {
        const name = `${n.name ?? ""}`.toLowerCase();
        return (root.cfg.screenExclude ?? []).some(p => p !== "" && name.indexOf(`${p}`.toLowerCase()) !== -1);
    }

    readonly property var videoSources: Pipewire.nodes.values.filter(n => root.isVideoSource(n))
    readonly property var screenNodes: root.videoSources.filter(n => !root.isCamera(n) && !root.excluded(n))
    readonly property var cameraNodes: root.videoSources.filter(n => root.isCamera(n))
    readonly property var links: Pipewire.links.values
    function consumersOf(nodes: var): var {
        const ids = nodes.map(n => n.id);
        return root.links.filter(l => l.source && l.target && ids.indexOf(l.source.id) !== -1).map(l => l.target);
    }
    readonly property bool cameraLinked: root.consumersOf(root.cameraNodes).length > 0
    readonly property bool cameraActive: root.cameraLinked || root.cameraProcs.length > 0

    function consumerName(nodes: var, fallback: string): string {
        const c = root.consumersOf(nodes);
        for (let i = c.length - 1; i >= 0; i--) {
            const p = c[i].properties ?? {};
            const name = p["application.name"] || p["application.process.binary"] || "";
            if (name !== "")
                return name;
        }
        return fallback;
    }

    PwObjectTracker {
        objects: [...root.consumersOf(root.screenNodes), ...root.consumersOf(root.cameraNodes)]
    }

    // Processes holding a V4L2 device (comm names, PipeWire's own excluded).
    property var cameraProcs: []
    Timer {
        running: root.cfg.cameraPollMs > 0
        interval: root.cfg.cameraPollMs
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!camProbe.running) camProbe.running = true
    }
    Process {
        id: camProbe
        command: ["sh", "-c", "for p in $(fuser /dev/video* 2>/dev/null); do cat /proc/$p/comm; done 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const ignore = root.cfg.cameraIgnore ?? [];
                const procs = this.text.split("\n").map(s => s.trim()).filter(s => s !== "" && ignore.indexOf(s) === -1);
                const uniq = [...new Set(procs)];
                if (JSON.stringify(uniq) !== JSON.stringify(root.cameraProcs))
                    root.cameraProcs = uniq;
            }
        }
    }
}
