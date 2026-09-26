import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Dictation: mic capture + speech-to-text hook. Captures to a temp file with
// `pw-record`; on stop, runs the configured transcriber command (if any) and
// emits transcribed(text). The DictationWave indicator is driven by `active`.
Item {
    id: root

    property bool active: false
    property string transcribeCommand: Config.data.dictation.transcribeCommand
    readonly property string captureFile: Config.data.dictation.captureFile

    signal transcribed(string text)

    function start(): void {
        if (active)
            return;
        active = true;
        recProc.command = ["pw-record", captureFile];
        recProc.running = true;
    }

    function stop(): void {
        if (!active)
            return;
        active = false;
        // SIGINT lets pw-record finalize the wav (pShell pattern).
        recProc.signal(2);
    }

    function toggle(): void {
        active ? stop() : start();
    }

    Process {
        id: recProc
        onExited: {
            if (root.transcribeCommand.length > 0) {
                transProc.command = ["bash", "-lc", root.transcribeCommand.replaceAll("{file}", root.captureFile)];
                transProc.running = true;
            }
        }
    }

    Process {
        id: transProc
        stdout: StdioCollector {
            onStreamFinished: root.transcribed(text.trim())
        }
    }

    IpcHandler {
        target: "dictation"
        function start(): void { root.start(); }
        function stop(): void { root.stop(); }
        function toggle(): void { root.toggle(); }
    }
}
