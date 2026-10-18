import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// CPU temperature + fan speeds from sysfs. Paths are discovered ONCE
// (hwmon "coretemp"/"k10temp"/... temp1 = package; every fan*_input under
// /sys/devices, incl. applesmc on T2 Macs, which is not in /sys/class/hwmon),
// then polled with one `cat` per tick. GPU hwmons (amdgpu/nouveau/radeon)
// are skipped: a runtime-suspended dGPU answers EBUSY, and reading it must
// never be a reason to wake it.
Item {
    id: root

    // Low Power Mode (services/PowerMode): Config.powerSave.pollFactor
    // times slower.
    property var powerMode: null
    readonly property int pollMs: (Config.data.dashboard.sysPollMs ?? 2000)
        * (root.powerMode?.active ? Math.max(1, Config.data.powerSave.pollFactor ?? 3) : 1)
    readonly property int historyLen: Config.data.dashboard.sensorHistory ?? 40

    // °C, NaN until the first sample / when no sensor exists.
    property real cpuTemp: NaN
    // Oldest-first °C samples for the sparkline (up to historyLen).
    property var tempHistory: []
    // [{ rpm, min, max }] per fan.
    property var fans: []
    readonly property bool hasFans: root.fans.length > 0
    readonly property real fanRpm: root.hasFans ? root.fans.reduce((a, f) => a + f.rpm, 0) / root.fans.length : 0
    // 0..1 between each fan's min and max, averaged.
    readonly property real fanFrac: root.hasFans ? root.fans.reduce((a, f) => a + Math.max(0, Math.min(1, (f.rpm - f.min) / Math.max(1, f.max - f.min))), 0) / root.fans.length : 0

    property string _tempPath: ""
    property var _fanSpecs: [] // [{ path, min, max }]
    property bool _discovered: false

    Process {
        id: discover
        running: true
        command: ["sh", "-c", `
            for h in /sys/class/hwmon/hwmon*; do
                case "$(cat "$h/name" 2>/dev/null)" in
                    coretemp|k10temp|zenpower|cpu_thermal) echo "T $h/temp1_input"; break ;;
                esac
            done
            find /sys/devices -maxdepth 9 -name 'fan[0-9]*_input' 2>/dev/null | while read -r f; do
                d=$(dirname "$f")
                case "$(cat "$d/name" 2>/dev/null)" in amdgpu|nouveau|radeon) continue ;; esac
                b=\${f%_input}
                echo "F $f $(cat "\${b}_min" 2>/dev/null || echo 0) $(cat "\${b}_max" 2>/dev/null || echo 0)"
            done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const specs = [];
                for (const line of text.split("\n")) {
                    const p = line.trim().split(/\s+/);
                    if (p[0] === "T")
                        root._tempPath = p[1];
                    else if (p[0] === "F")
                        specs.push({ path: p[1], min: +p[2] || 0, max: +p[3] || 0 });
                }
                root._fanSpecs = specs;
                root._discovered = true;
            }
        }
    }

    Timer {
        interval: root.pollMs
        repeat: true
        running: root._discovered && (root._tempPath !== "" || root._fanSpecs.length > 0)
        triggeredOnStart: true
        onTriggered: poll.running = true
    }

    // One line per path, in order; "x" for an unreadable one.
    Process {
        id: poll
        command: ["sh", "-c", "for f; do cat \"$f\" 2>/dev/null || echo x; done", "sh", root._tempPath || "/nonexistent"].concat(root._fanSpecs.map(s => s.path))
        stdout: StdioCollector {
            onStreamFinished: root._parse(text)
        }
    }

    function _parse(t: string): void {
        const v = t.split("\n").map(s => s.trim()).filter(s => s.length > 0);
        const temp = Number(v[0]) / 1000;
        if (isFinite(temp) && temp > 0) {
            root.cpuTemp = temp;
            const h = root.tempHistory.concat([temp]);
            root.tempHistory = h.length > root.historyLen ? h.slice(h.length - root.historyLen) : h;
        }
        const fans = [];
        root._fanSpecs.forEach((s, i) => {
            const rpm = Number(v[i + 1]);
            if (isFinite(rpm))
                fans.push({ rpm: rpm, min: s.min, max: s.max > 0 ? s.max : Math.max(rpm, 1) });
        });
        root.fans = fans;
    }
}
