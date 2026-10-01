import QtQuick
import Quickshell
import Quickshell.Io

// DictationStream: owns the streaming STT backend process and tails its
// JSONL session file (DICT_SESSION_FILE). Emits partial/final/error as lines
// flush; exited() fires when the backend process ends. File transport
// (whispy pattern): flushed lines survive lost signals and stalled pipes.
// The backend never prints to stdout (nothing would drain that pipe).
// start(cmd) takes the full `bash -lc` command (env already embedded).
// stop() sends SIGINT (backend flushes its final line, then exits 0) with a
// SIGKILL watchdog; kill() is the immediate SIGKILL for cancel(). A
// watchdog kill during a graceful stop is reported via watchdogKill so the
// orchestrator can finish normally off the tailed file instead of failing.
Item {
    id: root

    property int stopTimeoutMs: 7000
    property string sessionFile: ""
    property int sessionId: 0
    readonly property bool running: streamProc.running

    signal partial(string text)
    signal segment(string text, string lang)
    signal backendError(string message)
    // Backend loaded the model (session.updated acked). The orchestrator
    // uses it to leave the "switching" phase; first partial is the fallback
    // for backends that never send ready.
    signal ready()
    signal exited(int code, string errTail, int sid, bool watchdogKill)

    property int _cursor: 0
    // SID captured per run: onExited must report the exiting run's id, not
    // the current one — otherwise a late exit from a killed backend lands
    // in the new session (cancel + immediate start → bogus "exit 137").
    property int _runSid: 0
    property bool _watchdogFired: false

    function start(cmd: string): void {
        root._cursor = 0;
        root._runSid = root.sessionId;
        root._watchdogFired = false;
        streamProc.command = ["bash", "-lc", cmd];
        streamProc.running = true;
    }

    function stop(): void {
        if (!streamProc.running)
            return;
        streamProc.signal(2);
        stopWatchdog.restart();
    }

    function kill(): void {
        stopWatchdog.stop();
        if (streamProc.running)
            streamProc.signal(9);
    }

    // Pre-create the session file from the shell side, BEFORE the Loader
    // below binds FileView to the path: a FileView bound to a missing file
    // may never notice its later creation. The backend pre-creates too;
    // whichever wins, the file exists by the time the first line flushes.
    // Mode 0600 via umask: the file holds verbatim dictation.
    function prepare(path: string): void {
        if ((path ?? "").length === 0)
            return;
        touchProc.command = ["bash", "-c", 'umask 077; : >> "$1"', "dictation-touch", path];
        touchProc.running = true;
    }

    // Session tail: inotify picks every flush up without polling. Gated by
    // Loader so the FileView only exists while a session is active.
    Loader {
        id: sessionLoader
        active: root.sessionFile.length > 0
        sourceComponent: sessionComp
    }

    Component {
        id: sessionComp
        FileView {
            path: root.sessionFile
            watchChanges: true
            blockLoading: true
            onFileChanged: reload()
            onLoaded: root._drain()
            // Pre-created via prepare(); absent only in a narrow race.
            onLoadFailed: err => {
                if (err !== FileViewError.FileNotFound)
                    console.warn("[Dictation] session file:", err, root.sessionFile);
            }
        }
    }

    function drain(): void {
        if (sessionLoader.item)
            sessionLoader.item.reload();
        root._drain();
    }

    function _drain(): void {
        const view = sessionLoader.item;
        if (!view)
            return;
        let full = "";
        try {
            full = view.text() ?? "";
        } catch (e) {
            return;
        }
        const chunk = full.slice(root._cursor);
        if (chunk.length === 0)
            return;
        const lines = chunk.split("\n");
        const tail = lines.pop() ?? "";
        for (const ln of lines)
            root._handleLine(ln);
        if (tail.trim().length > 0 && !streamProc.running)
            root._handleLine(tail);
        else
            root._cursor = full.length - tail.length;
        if (!streamProc.running)
            root._cursor = full.length;
    }

    function _handleLine(ln: string): void {
        const s = (ln ?? "").trim();
        if (s.length === 0)
            return;
        let msg = null;
        try {
            msg = JSON.parse(s);
        } catch (e) {
            console.warn("[Dictation] bad line:", s);
            return;
        }
        if (msg.type === "partial")
            root.partial(msg.text ?? "");
        else if (msg.type === "final")
            root.segment(msg.text ?? "", msg.lang ?? "auto");
        else if (msg.type === "ready")
            root.ready();
        else if (msg.type === "error")
            root.backendError(msg.message ?? "stream error");
    }

    Process {
        id: touchProc
    }

    Process {
        id: streamProc
        stderr: StdioCollector {
            id: streamErr
        }
        onExited: code => {
            stopWatchdog.stop();
            pollTimer.stop();
            root.drain();
            root.exited(code, (streamErr.text ?? "").trim().slice(-300), root._runSid, root._watchdogFired);
            root._watchdogFired = false;
        }
        onRunningChanged: {
            if (running)
                pollTimer.restart();
            else
                pollTimer.stop();
        }
    }

    // Fallback poll: if FileView missed the session-file creation (it was
    // absent at bind time), inotify never fires and live partials would
    // arrive as one chunk on exit. drain() reloads first, so it works off
    // the file itself rather than the FileView cache.
    Timer {
        id: pollTimer
        interval: 300
        repeat: true
        onTriggered: {
            if (streamProc.running)
                root.drain();
        }
    }

    Timer {
        id: stopWatchdog
        interval: root.stopTimeoutMs
        onTriggered: {
            if (!streamProc.running)
                return;
            console.warn("[Dictation] stop timeout, killing stream");
            root._watchdogFired = true;
            streamProc.signal(9);
        }
    }
}
