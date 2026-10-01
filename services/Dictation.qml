import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Dictation orchestrator: streaming STT (DictationStream) -> wtype-only
// typing (DictationTyper) -> per-segment Refine (DictationRefine: text
// finalizer + optional Gemma 4 E2B over llama-server). Typing model:
// _committed (fixed segments) + _draft (live partial) form liveText; every
// change is pushed to the typer, which converges the screen via
// common-prefix + BackSpace + suffix. Refine never loses dictation: any
// stage failure falls through to the raw segment text.
//
// Session language: with followLayout the language comes from the
// KeyboardLayout service (compositor layout mapped through layout2lang),
// otherwise from Config `language`. A layout switch mid-session restarts
// the backend (switchMode "restart": SIGINT flush, then a new session in
// the new language — fast, but a mid-utterance switch splits the phrase;
// "dual" hot sessions are planned, not implemented).
Item {
    id: root

    // Live config (hot-reload; defaults in config/Config.qml).
    property string language: Config.data.dictation.language ?? "auto"
    property bool followLayout: Config.data.dictation.followLayout ?? true
    property string switchMode: Config.data.dictation.switchMode ?? "restart"
    // Injected by Shell (plain + null-safe: the service may be absent).
    property var keyboardLayout: null
    property int chunkMs: Config.data.dictation.chunkMs ?? 800
    property string streamCommand: Config.data.dictation.streamCommand ?? ""
    property string transcribeCommand: Config.data.dictation.transcribeCommand ?? ""
    readonly property string captureFile: Config.data.dictation.captureFile
    property bool typeEnabled: Config.data.dictation.typeEnabled ?? true
    property int stopTimeoutMs: Config.data.dictation.stopTimeoutMs ?? 7000

    property bool active: false
    // idle | switching | streaming | finalizing | refining
    // switching = backend (re)starting, model not loaded yet (grey wave);
    // leaves it on backend ready or on first audio, whichever comes first.
    property string phase: "idle"
    property string liveText: ""
    property string lastTranscript: ""
    property string lastError: ""
    // Effective ASR language of the running session (layout or config).
    readonly property string sessionLang: root._sessionLang
    readonly property string typedText: typer.typedText
    readonly property bool typeBusy: typer.busy

    signal partial(string text)
    signal segmentFinal(string text, string lang)
    signal refined(string text)
    signal transcribed(string text)
    signal failed(string message)

    property string _committed: ""
    property string _draft: ""
    // Raw segments accepted from the backend but not yet through Refine.
    // Shown in liveText while Gemma/finalizer works so the line never
    // flickers away (committed + pendingRaw + draft).
    property var _pendingTexts: []
    property int _pending: 0
    property bool _streamAlive: false
    property bool _finishing: false
    // Session epoch: guards late `exited` from a killed backend (cancel +
    // immediate start must not fail the new session).
    property int _sessionId: 0
    property string _sessionFile: ""
    property string _sessionLang: "auto"
    // Layout-driven restart: set when a layout switch stops the old
    // session; consumed by onExited/_finish to start the new one.
    property string _restartLang: ""
    property bool _restarting: false
    // First segment of a restarted session gets a leading space when the
    // previous session already typed text (cursor sits right after it).
    property bool _needLeadingSpace: false
    property bool _dualWarned: false
    readonly property string _runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") ?? "").length > 0 ? Quickshell.env("XDG_RUNTIME_DIR") : "/tmp"
    readonly property string _stub: `${Quickshell.shellDir}/scripts/dictation/stream-stub.sh`

    DictationTyper {
        id: typer
        onFailed: msg => root._fail(msg)
    }

    // Layout switch routing (restart mode). Manual stop/cancel wins: if the
    // user is already stopping, no restart is armed.
    Connections {
        target: root.keyboardLayout
        function onSwitched(lang, layout) {
            root._onLayoutSwitched(lang);
        }
    }

    DictationStream {
        id: stream
        stopTimeoutMs: root.stopTimeoutMs
        onPartial: text => {
            if (!root.active)
                return;
            root._draft = text;
            root._markStreaming();
            root._retype();
            root.partial(root._draft);
        }
        onSegment: (text, lang) => {
            if (!root.active)
                return;
            root._draft = "";
            root._markStreaming();
            root._onSegment(text, lang);
        }
        onReady: {
            if (!root.active)
                return;
            root._markStreaming();
        }
        onBackendError: msg => root._fail(msg)
        onExited: (code, tail, sid, watchdogKill) => {
            if (sid !== root._sessionId || !root.active)
                return;
            // 130 (SIGINT) / 143 (SIGTERM) while a graceful stop is in
            // flight: the wrapper died before exec'ing the backend (e.g.
            // Stop during the curl check) — treat as a normal exit.
            const ok = code === 0 || ((code === 130 || code === 143) && root._finishing);
            if (!ok) {
                // Watchdog kill after a graceful stop: the backend is deaf,
                // but whatever it flushed is already tailed from the file —
                // finish normally instead of dropping Refine work in _fail.
                if (watchdogKill && root._finishing) {
                    console.warn("[Dictation] stop timeout, finishing off tailed file");
                    root._streamAlive = false;
                    if (root._pending === 0)
                        root._finish();
                    else
                        root.phase = "finalizing";
                    return;
                }
                root._fail(`stream exit ${code}${tail.length > 0 ? ": " + tail : ""}`);
                return;
            }
            // Backend exited on its own (e.g. stub killed, mic died).
            // Pending Refine work must still land: mark finishing so
            // _maybeFinish() can close the session when it drains.
            // Layout restart consumes the exit instead when armed. Deferred
            // through a timer: (re)starting a Process from inside its own
            // onExited is untested territory in Quickshell — a timer fires
            // from a clean event-loop turn instead.
            root._streamAlive = false;
            if (root._restarting && root._restartLang.length > 0) {
                if (root._pending === 0) {
                    restartTimer.restart();
                } else {
                    root._finishing = true;
                    root.phase = "finalizing";
                }
                return;
            }
            if (root._pending === 0)
                root._finish();
            else {
                root._finishing = true;
                root.phase = "finalizing";
            }
        }
    }

    DictationRefine {
        id: refine
        finalizerCommand: Config.data.dictation.finalizerCommand ?? ""
        refineEnabled: Config.data.dictation.refineEnabled ?? false
        refineUrl: Config.data.dictation.refineUrl ?? ""
        refineModel: Config.data.dictation.refineModel ?? ""
        refinePrompt: Config.data.dictation.refinePrompt ?? ""
        refineTimeoutS: Config.data.dictation.refineTimeoutS ?? 15
        hallucinations: Config.data.dictation.hallucinations ?? []
        logFile: Config.data.dictation.logFile ?? ""
        onDone: (text, lang, how) => root._commit(text, lang, how)
        onDropped: (text, lang, reason) => {
            // Hallucination drops are routine, not errors: never pollute
            // lastError with them (already logged by Refine).
            root._shiftPending();
            root._retype();
            root._pending = Math.max(0, root._pending - 1);
            root._maybeFinish();
        }
    }

    function _effectiveLang(): string {
        if (root.followLayout) {
            const l = root.keyboardLayout?.lang ?? "";
            if (l.length > 0)
                return l;
        }
        return root.language;
    }

    function _onLayoutSwitched(lang: string): void {
        const l = lang ?? "";
        if (!root.followLayout || !root.active || root._legacyActive || root._finishing)
            return;
        if (l.length === 0 || l === root._sessionLang)
            return;
        if (root.switchMode !== "restart" && !root._dualWarned) {
            root._dualWarned = true;
            console.warn('[Dictation] switchMode "dual" (hot ru+en) not implemented yet — restarting');
        }
        // Restart initiation inlines stop() on purpose (instead of calling
        // it): stop() cancels an armed restart, which would wipe these very
        // flags. Legacy sessions never restart (transcriber owns language).
        console.warn(`[Dictation] layout switch: restart session in ${l}`);
        root._restartLang = l;
        root._restarting = true;
        if (stream.running) {
            root._finishing = true;
            root.phase = "finalizing";
            root._streamAlive = false;
            // SIGINT lets the backend flush its final line (pShell pattern).
            stream.stop();
        } else if (root._pending > 0) {
            root._finishing = true;
            root.phase = "finalizing";
            root._maybeFinish();
        } else {
            root._startSession(l);
        }
    }

    function start(): void {
        if (root.active)
            return;
        // A killed backend dies asynchronously: starting while the old
        // process still runs would overwrite _runSid and route its late
        // exit into the new session (bogus "stream exit 137"). Refuse;
        // the user retries once the old process reaps (milliseconds).
        if (stream.running || stream.starting || recProc.running || transProc.running) {
            console.warn("[Dictation] backend still stopping, start ignored");
            root.lastError = "backend still stopping — try again";
            return;
        }
        const sc = (root.streamCommand ?? "").trim();
        if (sc.length === 0 && (root.transcribeCommand ?? "").trim().length > 0) {
            root._sessionId += 1;
            root.lastError = "";
            root._committed = "";
            root._pendingTexts = [];
            root._draft = "";
            root.liveText = "";
            root.lastTranscript = "";
            root._pending = 0;
            root._finishing = false;
            root._legacyActive = false;
            root._restarting = false;
            root._restartLang = "";
            root._sessionLang = root._effectiveLang();
            typer.reset();
            typer.typeDelayMs = Config.data.dictation.typeDelayMs ?? 0;
            typer.typeEnabled = root.typeEnabled;
            root.phase = "streaming";
            root.active = true;
            root._streamAlive = false;
            root._legacySid = root._sessionId;
            root._legacyActive = true;
            recProc.command = ["pw-record", "--rate", "16000", "--channels", "1", root._effectiveCaptureFile()];
            recProc.running = true;
            return;
        }
        root._startSession(root._effectiveLang(), false);
    }

    // Streaming session body (also the layout-restart entry).
    // Never erases typed text: the cursor stays after the previous session,
    // so a restarted session arms a leading space for its first segment.
    function _startSession(lang: string, isRestart: bool): void {
        if (isRestart) {
            const prev = typer.typedText ?? "";
            root._needLeadingSpace = prev.length > 0 && !/\s$/.test(prev);
        } else {
            root._needLeadingSpace = false;
        }
        root._sessionId += 1;
        root.lastError = "";
        root._committed = "";
        root._pendingTexts = [];
        root._draft = "";
        root.liveText = "";
        root.lastTranscript = "";
        root._pending = 0;
        root._finishing = false;
        root._legacyActive = false;
        root._restarting = false;
        root._restartLang = "";
        root._sessionLang = (lang ?? "").length > 0 ? lang : "auto";
        typer.reset();
        typer.typeDelayMs = Config.data.dictation.typeDelayMs ?? 0;
        typer.typeEnabled = root.typeEnabled;
        const sc = (root.streamCommand ?? "").trim();
        const cmd = (sc.length === 0 || sc === "stub") ? root._stub : sc;
        const session = `${root._runtimeDir}/pillShell-dictation-${Date.now()}.jsonl`;
        root._sessionFile = session;
        stream.sessionId = root._sessionId;
        // Chained start (touch → FileView bind → backend): exact order,
        // never a same-tick race on the missing file.
        stream.prepareAndStart(session, `DICT_LANG='${root._sessionLang}' DICT_CHUNK_MS=${root.chunkMs} DICT_SESSION_FILE='${session}' ${cmd}`);
        root.phase = "switching";
        root.active = true;
        root._streamAlive = true;
    }

    function stop(): void {
        if (!root.active)
            return;
        if (root._finishing) {
            // Already stopping — possibly a layout restart in flight: a
            // manual stop disarms it, the stop itself proceeds to idle.
            root._restarting = false;
            root._restartLang = "";
            return;
        }
        if (stream.running) {
            root._finishing = true;
            root.phase = "finalizing";
            root._streamAlive = false;
            // SIGINT lets the backend flush its final line (pShell pattern).
            stream.stop();
        } else if (recProc.running || transProc.running) {
            root._finishing = true;
            if (recProc.running)
                recProc.signal(2);
        } else if (root._pending > 0) {
            // Backend already gone but Refine still holds segments:
            // wait for them instead of dropping the tail.
            root._finishing = true;
            root.phase = "finalizing";
            root._maybeFinish();
        } else {
            root._finish();
        }
    }

    function cancel(): void {
        if (!root.active)
            return;
        root._sessionId += 1;
        // Invalidate any chained backend start (touchProc completion checks
        // the stream sid and aborts on mismatch).
        stream.sessionId = root._sessionId;
        root._restarting = false;
        root._restartLang = "";
        refine.abort();
        stream.kill();
        if (recProc.running)
            recProc.signal(9);
        if (transProc.running)
            transProc.running = false;
        root._finishing = false;
        root._streamAlive = false;
        root._pending = 0;
        typer.eraseAll();
        root._committed = "";
        root._pendingTexts = [];
        root._draft = "";
        root.liveText = "";
        root.phase = "idle";
        root.active = false;
        root._removeSession(root._sessionFile);
        root._sessionFile = "";
        stream.sessionFile = "";
    }

    function toggle(): void {
        root.active ? root.stop() : root.start();
    }

    function status(): string {
        return JSON.stringify({
            active: root.active,
            phase: root.phase,
            lang: root._sessionLang,
            live: root.liveText,
            typed: root.typedText,
            last: root.lastTranscript,
            error: root.lastError
        });
    }

    // Backend confirmed live (ready ack) or audio is flowing (first
    // partial/segment): leave the grey "switching" phase. Guarded so a late
    // ready during finalizing never flips the phase back to streaming.
    function _markStreaming(): void {
        if (root.active && root.phase === "switching")
            root.phase = "streaming";
    }

    function _joinParts(parts: var): string {        let out = "";
        for (const p of parts) {
            const t = (p ?? "").trim();
            if (t.length === 0)
                continue;
            out = out.length > 0 ? `${out} ${t}` : t;
        }
        return out;
    }

    function _retype(): void {
        const pend = root._joinParts(root._pendingTexts);
        const head = root._committed.length > 0 ? (pend.length > 0 ? `${root._committed} ${pend}` : root._committed) : pend;
        root.liveText = root._draft.length > 0 ? (head.length > 0 ? `${head} ${root._draft}` : root._draft) : head;
        typer.applyText(root.liveText);
    }

    // Refine resolves segments strictly FIFO, so done/dropped always match
    // the head of the queue: a plain shift, never indexOf (a refined text
    // could coincidentally equal a later raw segment and remove the wrong
    // one).
    function _shiftPending(): void {
        if (root._pendingTexts.length > 0)
            root._pendingTexts.shift();
    }

    function _onSegment(text: string, lang: string): void {
        const t = (text ?? "").trim();
        if (t.length === 0) {
            root._retype();
            root._maybeFinish();
            return;
        }
        // Hallucination pre-filter (same whole-match rule as Refine):
        // routine drops never enter pending, so there is nothing to
        // remove out of order when the sync `dropped` fires.
        if (refine.isHallucination(t)) {
            console.warn("[Dictation] hallucination dropped:", t);
            refine._log({ event: "dropped", reason: "hallucination", text: t, lang: lang });
            root._retype();
            root._maybeFinish();
            return;
        }
        root.segmentFinal(t, lang);
        root._pendingTexts.push(t);
        root._pending += 1;
        // Show the raw segment immediately; the refined text replaces it
        // in place on done. While the mic is live the phase stays
        // "streaming" (a "Refining…" plate mid-speech would be noise; the
        // refined text simply lands when ready).
        if (!root._streamAlive)
            root.phase = "finalizing";
        root._retype();
        refine.process(t, lang);
    }

    function _commit(text: string, lang: string, how: string): void {
        if (!root.active) {
            root._shiftPending();
            root._pending = Math.max(0, root._pending - 1);
            return;
        }
        // Echo suppression lives in the Python backend (delta-gated), not
        // here: a QML time-window would also eat genuine quick repeats.
        // Restart seam: the cursor sits right after the previous session's
        // text, so the first committed segment gets a leading space.
        if (root._needLeadingSpace && (text ?? "").length > 0) {
            text = ` ${text}`;
            root._needLeadingSpace = false;
        }
        root._shiftPending();
        root._committed = root._committed.length > 0 ? `${root._committed} ${text}` : text;
        root.lastTranscript = text;
        root._retype();
        if (how === "refined")
            root.refined(text);
        root.transcribed(text);
        refine._log({ event: "accepted", how: how, text: text, lang: lang });
        root._pending = Math.max(0, root._pending - 1);
        if (root._streamAlive) {
            root.phase = "streaming";
        } else {
            root._maybeFinish();
        }
    }

    function _maybeFinish(): void {
        if (root._finishing && root._pending === 0 && !stream.running)
            root._finish();
    }

    function _finish(): void {
        // Layout restart consumes the finish: the old session file is
        // dropped, then the new session starts in place. `active` is never
        // touched on this path, so the indicator and wave don't blink.
        const rl = (root._restarting && root._restartLang.length > 0) ? root._restartLang : "";
        if (rl.length > 0) {
            root._removeSessionFile(root._sessionFile);
            root._sessionFile = "";
            stream.sessionFile = "";
            root._startSession(rl, true);
            return;
        }
        root._finishing = false;
        root._streamAlive = false;
        root._pending = 0;
        root._pendingTexts = [];
        root.phase = "idle";
        root.active = false;
        // Invalidate any chained backend start still in flight (touch done,
        // backend not yet spawned — e.g. Stop pressed within milliseconds of
        // Start): its sid check aborts instead of spawning into idle.
        root._sessionId += 1;
        stream.sessionId = root._sessionId;
        root._removeSession(root._sessionFile);
        root._sessionFile = "";
        stream.sessionFile = "";
    }

    // Deferred restart entry: starting the backend from a timer keeps us
    // out of any Process onExited context (see onExited above).
    Timer {
        id: restartTimer
        interval: 60
        onTriggered: {
            if (root._restarting && root._restartLang.length > 0 && root.active)
                root._startSession(root._restartLang, true);
        }
    }

    function _fail(msg: string): void {
        console.warn("[Dictation]", msg);
        root._sessionId += 1;
        stream.sessionId = root._sessionId;
        root._restarting = false;
        root._restartLang = "";
        refine.abort();
        // Never leave the mic running: kill the backend (SIGKILL, the
        // SIGINT flush already had its chance) and the legacy procs.
        stream.kill();
        if (recProc.running)
            recProc.signal(9);
        if (transProc.running)
            transProc.running = false;
        root.lastError = msg;
        root.failed(msg);
        root._streamAlive = false;
        root._finishing = false;
        root._pending = 0;
        root._pendingTexts = [];
        root.phase = "idle";
        root.active = false;
        root._removeSession(root._sessionFile);
        root._sessionFile = "";
        stream.sessionFile = "";
    }

    // $XDG_RUNTIME_DIR migration for the legacy wav/log paths: /tmp is
    // world-readable and never cleaned; the runtime dir is 0700 tmpfs.
    function _migrateTmp(p: string, fallbackName: string): string {
        const s = p ?? "";
        if (s.length === 0)
            return `${root._runtimeDir}/${fallbackName}`;
        if (s.startsWith("/tmp/"))
            return `${root._runtimeDir}/${s.slice(5)}`;
        return s;
    }

    function _effectiveCaptureFile(): string {
        return root._migrateTmp(root.captureFile, "pillShell-dictation.wav");
    }

    function _removeSessionFile(path: string): void {
        if ((path ?? "").length === 0)
            return;
        rmProc.command = ["rm", "-f", path];
        rmProc.running = true;
    }

    function _removeSession(path: string): void {
        root._removeSessionFile(path);
        // Legacy wav holds raw audio: drop it, but only when the legacy
        // path actually ran (no pointless rm per streaming session, and no
        // early-return skipping the wav when there was no session file).
        if (root._legacyActive) {
            root._legacyActive = false;
            rmCapProc.command = ["rm", "-f", root._effectiveCaptureFile()];
            rmCapProc.running = true;
        }
    }

    // Legacy batch path (streamCommand "" + transcribeCommand set): kept for
    // compatibility; the result flows through the same Refine + wtype chain.
    property int _legacySid: 0
    property bool _legacyActive: false
    Process {
        id: recProc
        onExited: {
            if (root._legacySid !== root._sessionId || !root.active)
                return;
            if ((root.transcribeCommand ?? "").length > 0) {
                transProc.command = ["bash", "-lc", root.transcribeCommand.replaceAll("{file}", root._effectiveCaptureFile())];
                transProc.running = true;
            } else if (root._finishing) {
                root._finish();
            }
        }
    }

    Process {
        id: transProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (root._legacySid !== root._sessionId || !root.active)
                    return;
                const t = (text ?? "").trim();
                if (t.length > 0)
                    root._onSegment(t, root.language);
                else if (root._finishing)
                    root._finish();
            }
        }
        onExited: code => {
            if (root._legacySid !== root._sessionId || !root.active)
                return;
            if (code !== 0)
                root._fail(`transcribe exit ${code}`);
        }
    }

    Process {
        id: rmProc
    }
    Process {
        id: rmCapProc
    }

    IpcHandler {
        target: "dictation"
        function start(): void {
            root.start();
        }
        function stop(): void {
            root.stop();
        }
        function toggle(): void {
            root.toggle();
        }
        function cancel(): void {
            root.cancel();
        }
        function status(): string {
            return root.status();
        }
    }
}
