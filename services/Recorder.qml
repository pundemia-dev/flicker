import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Screen recording: single source of truth for the wf-recorder process and
// the `recording` flag (drives the red clock plate). The compositor facade
// delegates startRecording/stopRecording here.
Item {
    id: root

    property bool recording: false
    property int elapsedSeconds: 0
    property bool canStop: recording
    readonly property string outputFile: Config.data.recorder.outputFile
    readonly property string pidFile: Config.data.recorder.pidFile
    readonly property string elapsedText: {
        const m = Math.floor(elapsedSeconds / 60).toString().padStart(2, "0");
        const s = (elapsedSeconds % 60).toString().padStart(2, "0");
        return `${m}:${s}`;
    }

    function start(region: string): void {
        if (recording)
            return;
        recProc.command = region.length > 0
                ? ["bash", "-lc", `wf-recorder -g '${region}' -f ${root.outputFile} >/dev/null 2>&1 & echo $! > ${root.pidFile}`]
                : ["bash", "-lc", `wf-recorder -f ${root.outputFile} >/dev/null 2>&1 & echo $! > ${root.pidFile}`];
        recProc.running = true;
        recording = true;
        elapsedSeconds = 0;
        tick.running = true;
    }

    function stop(): void {
        if (!recording)
            return;
        stopProc.running = true;
    }

    Process {
        id: recProc
        onExited: code => {
            if (code !== 0) {
                root.recording = false;
                tick.running = false;
            }
        }
    }

    Process {
        id: stopProc
        command: ["bash", "-lc", `if [ -f ${root.pidFile} ]; then kill -INT $(cat ${root.pidFile}) && rm -f ${root.pidFile}; fi`]
        onExited: {
            root.recording = false;
            root.tick.running = false;
        }
    }

    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: root.elapsedSeconds += 1
    }
}
