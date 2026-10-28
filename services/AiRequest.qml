import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// One streamed AI request through services/Ai.qml: send(request) starts the
// server if needed and, once it is up, connects to its socket FROM THIS
// PROCESS (Quickshell.Io Socket — the server only answers its own
// quickshell, by SO_PEERCRED) and writes the request + session token; the
// server's JSON lines come back as delta / done / failed / models. A new
// send() or abort() drops the running one (its late lines are ignored:
// `epoch`). Exactly one of done / failed per send that ran.
Scope {
    id: root
    required property var ai

    readonly property bool busy: root.pending !== null || root.live
    property var pending: null
    property string request: ""
    property int epoch: 0
    property int runEpoch: -1
    property bool live: false
    property bool finished: false
    property bool gotLine: false

    signal delta(string text)
    signal done
    signal failed(string message)
    signal models(var list)

    function send(req: var): void {
        root.abort();
        root.pending = req;
        root.ai.ensure();
        if (root.ai.serverReady)
            root.start();
        else
            startTimeout.restart();
    }
    function abort(): void {
        root.pending = null;
        startTimeout.stop();
        root.epoch++;
        root.live = false;
        sock.connected = false;
    }

    function start(): void {
        if (root.pending === null)
            return;
        startTimeout.stop();
        root.request = JSON.stringify(Object.assign({}, root.pending, { token: root.ai.sessionToken }));
        root.pending = null;
        root.finished = false;
        root.gotLine = false;
        root.epoch++;
        root.runEpoch = root.epoch;
        root.live = true;
        sock.connected = false;
        sock.connected = true;
    }
    function finish(ok: bool, message: string): void {
        if (root.finished)
            return;
        root.finished = true;
        root.live = false;
        sock.connected = false;
        root.request = "";
        if (ok)
            root.done();
        else
            root.failed(message);
    }

    Connections {
        target: root.ai
        function onServerReadyChanged(): void {
            if (root.ai.serverReady && root.pending !== null)
                root.start();
            else if (!root.ai.serverReady && root.live)
                root.finish(false, I18n.tr("AI server stopped"));
        }
    }
    // First start downloads the server's packages (uv): give it time.
    Timer {
        id: startTimeout
        interval: root.ai.cfg.startTimeoutMs ?? 90000
        onTriggered: {
            if (root.pending === null)
                return;
            root.pending = null;
            root.failed(I18n.tr("AI server did not start"));
        }
    }

    Socket {
        id: sock
        path: root.ai.socketPath
        onConnectedChanged: {
            if (sock.connected) {
                if (root.live && root.runEpoch === root.epoch) {
                    sock.write(root.request + "\n");
                    sock.flush();
                }
            } else if (root.live && root.runEpoch === root.epoch) {
                // Closed by the server: an answer without "done" still
                // counts; no answer at all = refused / crashed.
                if (root.gotLine)
                    root.finish(true, "");
                else
                    root.finish(false, I18n.tr("AI server refused the request"));
            }
        }
        onError: e => {
            if (root.live && root.runEpoch === root.epoch)
                root.finish(false, I18n.tr("AI server not reachable"));
        }
        parser: SplitParser {
            onRead: line => {
                if (!line || !root.live || root.runEpoch !== root.epoch)
                    return;
                let obj = null;
                try {
                    obj = JSON.parse(line);
                } catch (e) {
                    return;
                }
                root.gotLine = true;
                if (obj.type === "delta")
                    root.delta(obj.text ?? "");
                else if (obj.type === "models")
                    root.models(obj.models ?? []);
                else if (obj.type === "done")
                    root.finish(true, "");
                else if (obj.type === "error")
                    root.finish(false, obj.message ?? I18n.tr("AI error"));
            }
        }
    }
}
