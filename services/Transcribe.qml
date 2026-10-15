import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Speech-to-text of stash files (WhisperX, scripts/stash/transcribe.py).
// Child of services/Stash (`stash.transcribe`). Files are transcribed ONE
// AT A TIME in request order; the result JSON lands in
// cachePath("transcripts")/<md5(path)>.json and is shown by the stash
// `transcript` view. While a run is going the bar holds an event (transfer
// glyph with the live progress, queue count in the text).
// Every setting (model, language, device, alignment, diarization, ...) is
// `Config.transcribe`, read at the start of each run.
Scope {
    id: root
    required property var events

    readonly property var cfg: Config.data.transcribe
    readonly property string cacheDir: Quickshell.cachePath("transcripts")

    property var queue: []
    // The file being transcribed ("" = idle).
    property string current: ""
    // loading | transcribing | aligning | diarizing ("" = idle).
    property string stage: ""
    property real progress: 0
    // Cached results: { <md5(path)>: true }.
    property var known: ({})
    // Last failures: { <path>: message } (cleared by the next request).
    property var errors: ({})
    readonly property bool busy: root.current !== ""

    signal finished(string path)
    signal failed(string path, string message)

    function keyFor(path: string): string {
        return Qt.md5(path);
    }
    function resultFor(path: string): string {
        return `${root.cacheDir}/${root.keyFor(path)}.json`;
    }
    function hasResult(path: string): bool {
        return !!root.known[root.keyFor(path)];
    }
    // "" | "queued" | "running" | "done" | "error"
    function stateOf(path: string): string {
        if (path === root.current)
            return "running";
        if (root.queue.includes(path))
            return "queued";
        if (root.hasResult(path))
            return "done";
        return root.errors[path] !== undefined ? "error" : "";
    }

    function request(path: string): void {
        if (!path || root.stateOf(path) === "running" || root.stateOf(path) === "queued" || root.hasResult(path))
            return;
        root.clearError(path);
        root.queue = [...root.queue, path];
        if (!root.busy)
            root.next();
    }

    // Drop the cached result and transcribe again (settings changed).
    function rerun(path: string): void {
        if (root.stateOf(path) === "running" || root.stateOf(path) === "queued")
            return;
        const k = root.keyFor(path);
        const m = Object.assign({}, root.known);
        delete m[k];
        root.known = m;
        Quickshell.execDetached(["rm", "-f", root.resultFor(path)]);
        root.request(path);
    }

    function cancel(path: string): void {
        if (root.queue.includes(path)) {
            root.queue = root.queue.filter(p => p !== path);
        } else if (path === root.current) {
            root.cancelled = true;
            proc.signal(15);
        }
    }

    function clearError(path: string): void {
        if (root.errors[path] === undefined)
            return;
        const e = Object.assign({}, root.errors);
        delete e[path];
        root.errors = e;
    }

    function next(): void {
        if (root.queue.length === 0) {
            root.current = "";
            root.stage = "";
            root.progress = 0;
            return;
        }
        root.current = root.queue[0];
        root.queue = root.queue.slice(1);
        root.stage = "loading";
        root.progress = 0;
        root.cancelled = false;
        root.gotOutput = false;
        root.online = false;
        root.lastError = "";
        root.announce();
        proc.command = root.commandFor(root.current);
        proc.running = true;
    }

    function fileName(path: string): string {
        return path.split("/").pop();
    }

    // Once per file: the event informs (live text while it shows), then
    // leaves — the progress stays on as a status ring (services/StatusFeeds,
    // the event's `status` key keeps the ring inline while it shows).
    function announce(): void {
        if (!root.busy || !(Config.data.events.transcribe ?? true))
            return;
        root.events.post({
            key: "transcribe",
            status: "transcribe",
            glyph: "transfer",
            glyphArgs: { progress: null },
            icon: "", // tabler file-text (font fallback)
            text: () => root.stage === "loading" ? I18n.tr("Loading model…")
                : root.queue.length > 0 ? I18n.tr("%1% · %2 more").arg(Math.round(root.progress * 100)).arg(root.queue.length)
                : I18n.tr("Transcribing %1%").arg(Math.round(root.progress * 100))
        });
    }

    // One outcome per file (user: an event OR a notification, never both):
    // a ready transcript / a failure = notification (tap opens the
    // transcript view through IPC), a cancel = nothing (the user did it).
    // The start event leaves either way.
    function outcome(path: string, ok: bool, message: string): void {
        root.events.cancel("transcribe");
        const q = s => `'${String(s).replace(/'/g, "'\\''")}'`;
        const title = ok ? I18n.tr("Transcript ready") : I18n.tr("Transcription failed");
        const body = ok ? root.fileName(path) : `${root.fileName(path)}\n${message}`;
        Quickshell.execDetached(["bash", "-c",
            `a=$(notify-send -a pillShell -A default=${q(I18n.tr("Open"))} ${q(title)} ${q(body)}); `
            + `[ "$a" = default ] && quickshell ipc -p ${q(Quickshell.shellDir)} call island stashTranscript ${q(path)}`]);
    }

    // Offline first (CaptureActions.uvScript): online `uv run --script`
    // re-resolves deps on every start; a silent offline failure (env not
    // cached yet — the first run downloads torch + whisperx) retries online.
    property bool online: false
    property bool gotOutput: false
    property bool cancelled: false
    property string lastError: ""

    function commandFor(path: string): var {
        const c = root.cfg;
        const tok = c.hfToken !== "" ? c.hfToken : (Quickshell.env("HF_TOKEN") ?? "");
        const prio = c.nice > 0 ? ["nice", "-n", `${c.nice}`] : [];
        return [...prio, "uv", "run", "--quiet", ...(root.online ? [] : ["--offline"]),
            "--script", `${Quickshell.shellDir}/scripts/stash/transcribe.py`,
            "--file", path, "--out", root.resultFor(path),
            "--model", c.model, "--language", c.language, "--device", c.device,
            "--compute-type", c.computeType, "--batch-size", `${c.batchSize}`,
            "--threads", `${c.threads}`, "--vad", c.vad,
            "--align", c.align ? "1" : "0", "--diarize", c.diarize ? "1" : "0",
            "--hf-token", tok, "--min-speakers", `${c.minSpeakers}`,
            "--max-speakers", `${c.maxSpeakers}`, "--models-dir", root.expand(c.modelsDir)];
    }

    function expand(p: string): string {
        const home = Quickshell.env("HOME") ?? "";
        return p.startsWith("~") ? home + p.slice(1) : p.startsWith("$HOME") ? home + p.slice(5) : p;
    }

    function handle(line: string): void {
        let m;
        try {
            m = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (m.state === "done") {
            root.known = Object.assign({}, root.known, { [root.keyFor(root.current)]: true });
            root.stage = "done";
        } else if (m.state === "error") {
            root.lastError = m.message ?? "";
            console.warn("[Transcribe]", root.current, root.lastError);
        } else {
            root.stage = m.state;
            root.progress = m.progress ?? root.progress;
        }
    }

    Process {
        id: proc
        stdout: SplitParser {
            onRead: line => {
                root.gotOutput = true;
                root.handle(line);
            }
        }
        onExited: code => {
            const path = root.current;
            if (!root.cancelled && !root.gotOutput && !root.online) {
                root.online = true;
                proc.command = root.commandFor(path);
                proc.running = true;
                return;
            }
            if (root.stage === "done") {
                root.finished(path);
                root.outcome(path, true, "");
            } else if (root.cancelled) {
                root.events.cancel("transcribe");
            } else {
                const msg = root.lastError !== "" ? root.lastError : I18n.tr("exit code %1").arg(code);
                root.errors = Object.assign({}, root.errors, { [path]: msg });
                root.failed(path, msg);
                root.outcome(path, false, msg);
            }
            root.next();
        }
    }

    // ── Writing text out (copy / save) ──
    // Through stdin, never argv: an hour of speech is past the 128 KB limit
    // of one exec argument. Queued: a write while one runs waits.
    property var writes: []
    signal written(string target)

    function pipe(cmd: var, text: string, target: string): void {
        root.writes = [...root.writes, { cmd, text, target }];
        if (!writer.running)
            root.nextWrite();
    }
    function copy(text: string): void {
        root.pipe(["wl-copy"], text, "");
    }
    function save(path: string, text: string): void {
        root.pipe(["bash", "-c", 'mkdir -p "$(dirname "$1")" && cat > "$1"', "_", path], text, path);
    }
    function nextWrite(): void {
        if (root.writes.length === 0)
            return;
        writer.job = root.writes[0];
        root.writes = root.writes.slice(1);
        writer.command = writer.job.cmd;
        writer.running = true;
    }

    Process {
        id: writer
        property var job: null
        stdinEnabled: true
        onStarted: {
            writer.write(writer.job.text);
            writer.stdinEnabled = false;
        }
        onExited: code => {
            writer.stdinEnabled = true;
            if (code === 0 && writer.job.target !== "")
                root.written(writer.job.target);
            root.nextWrite();
        }
    }

    // Results already in the cache (earlier sessions).
    Process {
        id: scan
        command: ["bash", "-c", `mkdir -p '${root.cacheDir}' && ls -1 '${root.cacheDir}'`]
        stdout: StdioCollector {
            id: scanOut
            onStreamFinished: {
                const m = {};
                for (const n of scanOut.text.split("\n"))
                    if (n.endsWith(".json"))
                        m[n.slice(0, -5)] = true;
                root.known = m;
            }
        }
    }
    Component.onCompleted: scan.running = true
}
