import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Live CPU / RAM / root-disk usage + top processes (pShell SystemUsage
// pattern: /proc/stat jiffy deltas, /proc/meminfo, df, ps). Fractions are
// 0..1, raw sizes in bytes. Polled, no C++ involved.
Item {
    id: root

    readonly property int pollMs: Config.data.dashboard.sysPollMs ?? 2000

    property real cpuPerc: 0
    property real memPerc: 0
    property real storagePerc: 0

    property real memUsed: 0
    property real memTotal: 0
    property real storageUsed: 0
    property real storageTotal: 0

    // Newest-first [{ name: string, cpu: real }], up to 5 entries.
    property var topProcesses: []

    property var _prevCpu: null

    function formatGib(bytes: real): string {
        if (!(bytes > 0))
            return "—";
        return `${(bytes / 1073741824).toFixed(1)} ГиБ`;
    }

    Timer {
        interval: root.pollMs
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            statFv.reload();
            memFv.reload();
            dfProc.running = true;
            psProc.running = true;
        }
    }

    FileView {
        id: statFv
        path: "/proc/stat"
        onLoaded: root._parseCpu(text())
    }

    FileView {
        id: memFv
        path: "/proc/meminfo"
        onLoaded: root._parseMem(text())
    }

    Process {
        id: dfProc
        command: ["df", "-B1", "--output=size,used", "/"]
        stdout: StdioCollector {
            onStreamFinished: root._parseDf(text)
        }
    }

    Process {
        id: psProc
        command: ["sh", "-c", "ps -eo comm:25,pcpu --sort=-pcpu | head -n 7"]
        stdout: StdioCollector {
            onStreamFinished: root._parsePs(text)
        }
    }

    function _parseCpu(t: string): void {
        const line = t.split("\n")[0];
        if (!line || !line.startsWith("cpu"))
            return;
        const p = line.trim().split(/\s+/).slice(1).map(Number);
        const idle = (p[3] || 0) + (p[4] || 0); // idle + iowait
        const total = p.reduce((a, b) => a + b, 0);
        if (root._prevCpu) {
            const dt = total - root._prevCpu.total;
            const di = idle - root._prevCpu.idle;
            if (dt > 0)
                root.cpuPerc = Math.max(0, Math.min(1, 1 - di / dt));
        }
        root._prevCpu = { total: total, idle: idle };
    }

    function _parseMem(t: string): void {
        const get = k => {
            const m = t.match(new RegExp(k + ":\\s+(\\d+)"));
            return m ? Number(m[1]) * 1024 : 0;
        };
        const total = get("MemTotal");
        const avail = get("MemAvailable");
        if (total <= 0)
            return;
        root.memTotal = total;
        root.memUsed = Math.max(0, total - avail);
        root.memPerc = root.memUsed / total;
    }

    function _parseDf(t: string): void {
        const lines = t.trim().split("\n");
        if (lines.length < 2)
            return;
        const parts = lines[1].trim().split(/\s+/).map(Number);
        if (!(parts[0] > 0))
            return;
        root.storageTotal = parts[0];
        root.storageUsed = parts[1];
        root.storagePerc = parts[1] / parts[0];
    }

    function _parsePs(t: string): void {
        const out = [];
        const lines = t.trim().split("\n");
        for (let i = 1; i < lines.length && out.length < 5; i++) {
            const parts = lines[i].trim().split(/\s+/);
            if (parts.length < 2)
                continue;
            const name = parts[0] ?? "";
            const cpu = parseFloat(parts[1] ?? "0");
            if (!name || name === "ps" || isNaN(cpu))
                continue;
            out.push({ name: name, cpu: cpu });
        }
        root.topProcesses = out;
    }
}
