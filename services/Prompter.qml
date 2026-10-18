import QtQuick
import Quickshell
import Quickshell.Io
import "../config"
import "../modules/prompter/PrompterParse.js" as Parse
import "../modules/prompter/PrompterAlign.js" as Align

// Teleprompter state (modules/prompter shows it in the island). Owns the
// script (markdown → PrompterParse doc), the reading cursor and the mode:
//   voice  — follows speech: Dictation runs with sink "prompter" (nothing
//            typed, no Refine) and every partial/final goes through
//            PrompterAlign; off-script talk is simply not matched and the
//            first words back on the script re-acquire the position
//   auto   — constant pace (cfg.wpm)
//   manual — wheel / keys only (also works in the other modes as a nudge)
// `cursor` = index (doc.words) of the next word to read. The file is
// watched: an edit re-parses and re-locates the cursor by its last words.
// Last file + position per file persist in statePath("prompter.json").
Scope {
    id: root

    property var dictation: null
    readonly property var cfg: Config.data.prompter

    // Module wanted on screen (Island routes show/hide).
    property bool open: false
    property string path: ""
    property var doc: ({ blocks: [], words: [] })
    property int cursor: 0
    property string mode: root.cfg?.mode ?? "voice"
    // setMode (IPC, the module) breaks the binding: a config change still wins.
    readonly property string cfgMode: root.cfg?.mode ?? "voice"
    onCfgModeChanged: root.setMode(root.cfgMode)
    property bool paused: false
    // voice: "starting" | "listening" | "lost" | "error"; else idle.
    property string voiceState: "idle"
    property string lastError: ""
    readonly property string lang: (root.cfg?.language ?? "auto") !== "auto" ? root.cfg.language : Parse.detectLang(root.doc.words)
    readonly property real progress: root.doc.words.length > 0 ? root.cursor / root.doc.words.length : 0
    readonly property bool empty: root.doc.words.length === 0
    readonly property bool listening: root.dictation?.active === true && root.dictation?.sink === "prompter"

    signal showRequested
    signal hideRequested

    // Spoken words (alignment script) and word → spoken-prefix counts.
    property var _spoken: []
    property var _script: []
    property var _before: [0]
    // Heard words: finals (trimmed, abs-indexed via _finalCount) + partial.
    property var _finals: []
    property int _finalCount: 0
    property var _partial: []
    property int _lastMatch: -1
    property real _lastGlobal: 0
    property real _autoPos: 0
    property var _positions: ({})

    function _expand(p: string): string {
        const s = (p ?? "").trim();
        return s.startsWith("~/") ? `${Quickshell.env("HOME")}/${s.slice(2)}` : s;
    }

    // ── loading ──
    function openFile(p: string): void {
        const full = root._expand(p);
        if (full.length === 0)
            return;
        root._savePosition();
        if (full === root.path)
            scriptFile.reload();
        root.path = full;
        root.show();
    }

    function openText(text: string): void {
        root._savePosition();
        root.path = "";
        root._setSource(text ?? "", false);
        root.show();
    }

    function openClipboard(): void {
        clipProc.running = true;
    }

    function _setSource(src: string, keep: bool): void {
        const oldWords = root.doc.words;
        const oldCursor = root.cursor;
        const d = Parse.parse(src);
        const spoken = [], script = [], before = [0];
        for (let i = 0; i < d.words.length; i++) {
            if (d.words[i].spoken) {
                spoken.push(i);
                script.push(d.words[i].norm);
            }
            before.push(spoken.length);
        }
        root._spoken = spoken;
        root._script = script;
        root._before = before;
        root.doc = d;
        let c = 0;
        if (keep) {
            // Re-locate by the last few read words (edit above the cursor
            // shifts indices); fall back to the same relative position.
            const tail = [];
            for (let i = Math.min(oldCursor, oldWords.length) - 1; i >= 0 && tail.length < 8; i--)
                if (oldWords[i].spoken)
                    tail.unshift(oldWords[i].norm);
            const r = tail.length >= 3 ? Align.step(script, { cursor: 0, lastMatch: -100 }, tail, tail.length, { globalAfter: 0 }) : null;
            c = r && r.cursor > 0 ? root._wordAfterSpoken(r.cursor)
                : Math.round(oldCursor / Math.max(1, oldWords.length) * d.words.length);
        } else if (root.path.length > 0) {
            c = root._positions[root.path] ?? 0;
        }
        root._resetHeard();
        root.setCursor(c);
    }

    // Word index right after the s-th spoken word (s = spoken count read).
    function _wordAfterSpoken(s: int): int {
        if (s <= 0)
            return 0;
        return s > root._spoken.length ? root.doc.words.length : root._spoken[s - 1] + 1;
    }

    function setCursor(c: int): void {
        root.cursor = Math.max(0, Math.min(root.doc.words.length, c));
        root._autoPos = root.cursor;
        saveTimer.restart();
    }

    // ── visibility / session ──
    function show(): void {
        if (root.empty && root.path.length === 0 && (root._positions.__last ?? "").length > 0)
            root.path = root._positions.__last;
        root.open = true;
        root.showRequested();
        root._applyMode();
    }

    function close(): void {
        if (!root.open)
            return;
        root.open = false;
        root._stopVoice();
        root._savePosition();
        root.hideRequested();
    }

    function toggle(): void {
        root.open ? root.close() : root.show();
    }

    function setMode(m: string): void {
        if (!["voice", "auto", "manual"].includes(m))
            return;
        root.mode = m;
        root.paused = false;
        root._applyMode();
    }

    function cycleMode(): void {
        const all = ["voice", "auto", "manual"];
        root.setMode(all[(all.indexOf(root.mode) + 1) % all.length]);
    }

    function togglePause(): void {
        root.paused = !root.paused;
        // Words said while paused must not drag the cursor on resume.
        root._resetHeard();
        root._autoPos = root.cursor;
    }

    function _applyMode(): void {
        if (root.open && root.mode === "voice" && !root.empty)
            root._startVoice();
        else
            root._stopVoice();
    }

    function _startVoice(): void {
        if (!root.dictation || root.listening)
            return;
        if (root.dictation.active) {
            root.voiceState = "error";
            root.lastError = I18n.tr("Dictation is busy");
            return;
        }
        root._resetHeard();
        root.lastError = "";
        root.voiceState = "starting";
        root.dictation.startFor("prompter", root.lang);
    }

    function _stopVoice(): void {
        if (root.listening)
            root.dictation.stop();
        root.voiceState = "idle";
    }

    onLangChanged: {
        // A script in another language needs a session in that language.
        if (root.listening) {
            root.dictation.cancel();
            restartVoice.restart();
        }
    }
    Timer {
        id: restartVoice
        interval: 150
        onTriggered: root._applyMode()
    }
    onEmptyChanged: root._applyMode()

    // ── navigation ──
    function moveBy(words: int): void {
        root.setCursor(root.cursor + words);
        root._resetHeard();
    }

    // Start of the next / previous block.
    function jumpBlock(dir: int): void {
        const blocks = root.doc.blocks;
        if (blocks.length === 0)
            return;
        const cur = root.cursor < root.doc.words.length ? root.doc.words[root.cursor].block : blocks.length - 1;
        let b = cur + dir;
        if (dir < 0 && root.cursor > blocks[cur].first)
            b = cur;
        while (b >= 0 && b < blocks.length && blocks[b].count === 0)
            b += dir < 0 ? -1 : 1;
        if (b < 0)
            root.setCursor(0);
        else if (b >= blocks.length)
            root.setCursor(root.doc.words.length);
        else
            root.setCursor(blocks[b].first);
        root._resetHeard();
    }

    // ── voice tracking ──
    function _resetHeard(): void {
        root._finals = [];
        root._finalCount = 0;
        root._partial = [];
        root._lastMatch = -1;
        if (root.voiceState === "lost")
            root.voiceState = "listening";
    }

    function _tokens(text: string): var {
        return (text ?? "").split(/\s+/).map(Parse.normalize).filter(t => t.length > 0);
    }

    function _track(): void {
        if (root.paused || root.mode !== "voice" || root._script.length === 0)
            return;
        const heard = root._finals.concat(root._partial);
        const now = Date.now();
        const ac = root.cfg?.align ?? {};
        const r = Align.step(root._script, {
            cursor: root._before[Math.min(root.cursor, root.doc.words.length)],
            lastMatch: root._lastMatch
        }, heard, root._finalCount + root._partial.length,
            Object.assign({}, ac, { allowGlobal: now - root._lastGlobal >= (root.cfg?.globalThrottleMs ?? 300) }));
        if (r.searched)
            root._lastGlobal = now;
        root._lastMatch = r.lastMatch;
        const c = root._wordAfterSpoken(r.cursor);
        if (c !== root.cursor && r.cursor !== root._before[root.cursor])
            root.setCursor(c);
        root.voiceState = r.lost ? "lost" : "listening";
    }

    Connections {
        target: root.dictation
        enabled: root.listening
        function onPartial(text) {
            root._partial = root._tokens(text);
            root._track();
        }
        function onSegmentFinal(text, lang) {
            const t = root._tokens(text);
            const keep = root.cfg?.heardKeep ?? 40;
            root._finals = root._finals.concat(t).slice(-keep);
            root._finalCount += t.length;
            root._partial = [];
            root._track();
        }
        function onPhaseChanged() {
            if (root.dictation.phase === "streaming" && root.voiceState === "starting")
                root.voiceState = "listening";
        }
    }
    Connections {
        target: root.dictation
        function onFailed(message) {
            if (root.mode === "voice" && root.open) {
                root.voiceState = "error";
                root.lastError = message;
            }
        }
        function onActiveChanged() {
            // Backend gone on its own while we still want to listen.
            if (!root.dictation.active && root.open && root.mode === "voice" && root.voiceState !== "error")
                root.voiceState = "idle";
        }
    }

    // ── auto pace ──
    Timer {
        interval: 100
        repeat: true
        running: root.open && root.mode === "auto" && !root.paused && root.cursor < root.doc.words.length
        onTriggered: {
            root._autoPos += (root.cfg?.wpm ?? 130) / 600;
            // Notes / code are not read aloud: skip them at once.
            let p = Math.floor(root._autoPos);
            while (p < root.doc.words.length && !root.doc.words[p].spoken && p >= root.cursor)
                p++;
            if (p > root.cursor) {
                root.cursor = Math.min(root.doc.words.length, p);
                root._autoPos = Math.max(root._autoPos, p);
                saveTimer.restart();
            }
        }
    }

    // ── files / persistence ──
    FileView {
        id: scriptFile
        path: root.path
        watchChanges: true
        printErrors: false
        property bool first: true
        onPathChanged: first = true
        onFileChanged: reload()
        onLoaded: {
            root._setSource(scriptFile.text(), !scriptFile.first);
            scriptFile.first = false;
        }
        onLoadFailed: err => {
            root.lastError = I18n.tr("Cannot read %1").arg(root.path);
            console.warn("[Prompter] cannot read", root.path, err);
        }
    }

    Process {
        id: clipProc
        command: ["wl-paste", "-n", "-t", "text"]
        stdout: StdioCollector {
            onStreamFinished: {
                if ((text ?? "").trim().length > 0)
                    root.openText(text);
            }
        }
    }

    function _savePosition(): void {
        if (root.path.length === 0)
            return;
        const p = Object.assign({}, root._positions);
        p[root.path] = root.cursor;
        p.__last = root.path;
        root._positions = p;
        stateFile.setText(JSON.stringify(p));
    }

    Timer {
        id: saveTimer
        interval: 2000
        onTriggered: root._savePosition()
    }

    FileView {
        id: stateFile
        path: Quickshell.statePath("prompter.json")
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                root._positions = JSON.parse(stateFile.text()) ?? {};
            } catch (e) {
                root._positions = {};
            }
        }
    }

    function status(): string {
        return JSON.stringify({
            open: root.open,
            path: root.path,
            mode: root.mode,
            paused: root.paused,
            voice: root.voiceState,
            lang: root.lang,
            cursor: root.cursor,
            words: root.doc.words.length,
            word: root.doc.words[root.cursor]?.text ?? "",
            heard: root._finals.concat(root._partial).slice(-8).join(" "),
            error: root.lastError
        });
    }

    IpcHandler {
        target: "prompter"
        function open(path: string): void { root.openFile(path); }
        function clipboard(): void { root.openClipboard(); }
        function text(content: string): void { root.openText(content); }
        function show(): void { root.show(); }
        function close(): void { root.close(); }
        function toggle(): void { root.toggle(); }
        function pause(): void { root.togglePause(); }
        // voice | auto | manual
        function mode(m: string): void { root.setMode(m); }
        function move(words: int): void { root.moveBy(words); }
        function next(): void { root.jumpBlock(1); }
        function prev(): void { root.jumpBlock(-1); }
        function status(): string { return root.status(); }
    }
}
