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
    // Backend spawn chained behind touch completion (not yet running).
    readonly property bool starting: touchProc.running

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
    // Chained-start state (see prepareAndStart): touch completion carries
    // the sid it was launched with and aborts on mismatch.
    property string _pendingSession: ""
    property string _pendingCmd: ""
    property int _chainSid: -1

    // Ordered start: the session file is pre-created FIRST, and only its
    // completion binds FileView (Loader) and spawns the backend. Binding
    // FileView to a missing file risks it never noticing the creation, and
    // a same-tick spawn loses that race — the chain makes the order exact.
    function prepareAndStart(path: string, cmd: string): void {
        root._cursor = 0;
        root._runSid = root.sessionId;
        root._chainSid = root.sessionId;
        root._watchdogFired = false;
        root._pendingSession = path ?? "";
        root._pendingCmd = cmd ?? "";
        touchProc.command = ["bash", "-c", 'umask 077; : >> "$1"', "dictation-touch", path];
        touchProc.running = true;
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

    // Session tail: inotify picks every flush up without polling. Gated by
    // Loader so the FileView only exists while a session is active.
    // NOTE: sessionFile is assigned only from touchProc completion (see
    // below), i.e. always to an existing file — never bind it directly.
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
        onExited: code => {
            // Superseded (cancel/fail bumped the sid meanwhile): abort the
            // chain instead of spawning a backend into a dead session.
            if (root._chainSid !== root.sessionId)
                return;
            const path = root._pendingSession;
            const cmd = root._pendingCmd;
            root._pendingSession = "";
            root._pendingCmd = "";
            if (path.length === 0 || cmd.length === 0)
                return;
            // File exists now (touch ran first): bind FileView, then spawn.
            root.sessionFile = path;
            streamProc.command = ["bash", "-lc", cmd];
            streamProc.running = true;
        }
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
