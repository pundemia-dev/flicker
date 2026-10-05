import QtQuick
import Quickshell.Io
import "../config"

// Small spectrum visualizer: `Config.visualizer.bars` vertical pills
// centred on the box, heights fed by cava (pShell RecordPill pattern: raw
// ascii frames on stdout, 0..100 per bar). cava listens to the default
// output's monitor (pulse "auto", mono) and runs ONLY while `active` — the
// owner binds that to "shown and playing". Its capture stream (binary
// "cava") is filtered out of the mic indicator (services/Audio
// isShellCapture). Idle / stopped = bars rest as dots.
Item {
    id: root
    property bool active: false
    property color color: "#F0F4FB"

    readonly property var cfg: Config.data.visualizer
    readonly property int bars: root.cfg?.bars ?? 6
    readonly property real barWidth: root.cfg?.barWidth ?? 3
    readonly property real gap: Math.max(0, (root.width - root.bars * root.barWidth) / Math.max(1, root.bars - 1))
    readonly property real maxHeight: root.height * (root.cfg?.heightRatio ?? 0.6)
    property var levels: []

    onActiveChanged: if (!root.active) root.levels = []

    Process {
        running: root.active
        command: ["bash", "-c", `cfg="$(mktemp -t pillshell_cava.XXXXXX)"
printf '[general]\\nbars = %d\\nframerate = %d\\n[input]\\nmethod = pulse\\nsource = auto\\n[output]\\nchannels = mono\\nmethod = raw\\nraw_target = /dev/stdout\\ndata_format = ascii\\nascii_max_range = 100\\nbar_delimiter = 59\\nframe_delimiter = 10\\n' ${root.bars} ${root.cfg?.framerate ?? 30} > "$cfg"
(sleep 2; rm -f "$cfg") &
exec cava -p "$cfg"`]
        stdout: SplitParser {
            onRead: data => root.levels = data.split(";").filter(s => s !== "").map(Number)
        }
    }

    Repeater {
        model: root.bars

        Rectangle {
            required property int index
            x: Math.round(index * (root.barWidth + root.gap))
            width: root.barWidth
            radius: width / 2
            color: root.color
            readonly property real level: Math.max(0, Math.min(1, (root.levels[index] ?? 0) / 100))
            height: Math.max(width, level * root.maxHeight)
            y: (root.height - height) / 2
            Behavior on height { Spring { stiffness: 8; damp: 0.6; eps: 0.1 } }
        }
    }
}
