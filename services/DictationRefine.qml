import QtQuick
import Quickshell
import Quickshell.Io

// DictationRefine: per-segment post-processing — hallucination filter,
// optional text finalizer, optional Gemma 4 E2B Refine over llama-server.
// Contract: process(text, lang) enqueues a segment; exactly one of
// done/dropped fires per call, in order (internal FIFO — the single
// finalizer/refiner Process never overlaps with itself). abort() kills
// in-flight work, clears the queue and suppresses late callbacks (epoch
// guard), so cancel() never commits stale text. Never loses dictation:
// any stage failure falls through to the raw segment.
Item {
    id: root

    property string finalizerCommand: ""
    property bool refineEnabled: false
    property string refineUrl: "http://127.0.0.1:8080/v1/chat/completions"
    property string refineModel: ""
    property string refinePrompt: ""
    property int refineTimeoutS: 15
    property var hallucinations: []
    property string logFile: "/tmp/pillShell-dictation.jsonl"

    signal done(string text, string lang, string how)
    signal dropped(string text, string lang, string reason)

    property var _queue: []
    property bool _busy: false
    property int _epoch: 0
    property string _segText: ""
    property string _segLang: ""
    property string _refineFallback: ""
    property string _refineLang: ""
    property var _logQueue: []
    property string _finStdout: ""
    property string _refineStdout: ""

    function _normalize(s: string): string {
        let t = (s ?? "").toLowerCase().trim().replace(/\s+/g, " ");
        t = t.replace(/[.,!?;:…"«»„“”\(\)\[\]\-—–_*#@]+/g, "");
        return t.trim().replace(/\s+/g, " ");
    }

    // Whole-match rule: a hallucination phrase drops the segment only when
    // the segment (almost) IS the phrase — never when a long dictation
    // merely contains a common word like "спасибо".
    function isHallucination(text: string): bool {
        const seg = root._normalize(text);
        if (seg.length === 0)
            return false;
        for (const h of (root.hallucinations ?? [])) {
            const ph = root._normalize(h);
            if (ph.length === 0)
                continue;
            if (seg === ph)
                return true;
            const segWords = seg.split(" ");
            const phWords = ph.split(" ");
            if (segWords.length <= phWords.length + 1 && seg.indexOf(ph) !== -1)
                return true;
        }
        return false;
    }

    function process(text: string, lang: string): void {
        const t = (text ?? "").trim();
        if (t.length === 0)
            return;
        if (root.isHallucination(t)) {
            console.warn("[Dictation] hallucination dropped:", t);
            root._log({ event: "dropped", reason: "hallucination", text: t, lang: lang });
            root.dropped(t, lang, "hallucination");
            return;
        }
        root._queue.push({ text: t, lang: lang });
        if (!root._busy)
            root._next();
    }

    function abort(): void {
        root._epoch += 1;
        root._queue = [];
        root._busy = false;
        if (finProc.running)
            finProc.running = false;
        if (refineProc.running)
            refineProc.running = false;
    }

    function _next(): void {
        if (root._queue.length === 0) {
            root._busy = false;
            return;
        }
        root._busy = true;
        const head = root._queue.shift();
        const fin = (root.finalizerCommand ?? "").trim();
        if (fin.length > 0) {
            root._segText = head.text;
            root._segLang = head.lang;
            // Segment text as $1, lang as $2; stdout = improved text.
            finProc.command = ["bash", "-c", fin, "dictation-finalizer", head.text, head.lang];
            finProc.running = true;
        } else {
            root._refineOrCommit(head.text, head.lang);
        }
    }

    function _emitDone(text: string, lang: string, how: string): void {
        root.done(text, lang, how);
        root._next();
    }

    function _refineOrCommit(text: string, lang: string): void {
        if (root.refineEnabled) {
            root._refineFallback = text;
            root._refineLang = lang;
            const payload = JSON.stringify({
                model: root.refineModel,
                messages: [
                    { role: "system", content: root.refinePrompt },
                    { role: "user", content: `<transcript>${text}</transcript>` }
                ],
                temperature: 0.1,
                max_tokens: 256
            });
            refineProc.command = ["curl", "-4", "-fsS", "--max-time", String(root.refineTimeoutS),
                "-X", "POST", root.refineUrl, "-H", "Content-Type: application/json",
                "--data-binary", payload];
            refineProc.running = true;
        } else {
            root._emitDone(text, lang, "raw");
        }
    }

    function _log(obj: var): void {
        if ((root._effectiveLogFile() ?? "").length === 0)
            return;
        root._logQueue.push(JSON.stringify(obj));
        root._pumpLog();
    }

    function _pumpLog(): void {
        if (logProc.running || root._logQueue.length === 0)
            return;
        const line = root._logQueue.shift();
        // umask 077 + chmod: transcripts are sensitive; never 0644, and
        // fix up a pre-existing world-readable file from older versions.
        logProc.command = ["bash", "-c", 'umask 077; printf \'%s\\n\' "$1" >> "$2"; chmod 600 "$2" 2>/dev/null', "dictation-log", line, root._effectiveLogFile()];
        logProc.running = true;
    }

    // Log transcripts are private but on by default (as before): an absent
    // logFile falls back to $XDG_RUNTIME_DIR (0700 tmpfs), a /tmp path
    // migrates there too; explicit non-/tmp paths are used as-is.
    function _effectiveLogFile(): string {
        const rt = (Quickshell.env("XDG_RUNTIME_DIR") ?? "").length > 0 ? Quickshell.env("XDG_RUNTIME_DIR") : "/tmp";
        const s = root.logFile ?? "";
        if (s.length === 0)
            return `${rt}/pillShell-dictation.jsonl`;
        if (s.startsWith("/tmp/"))
            return `${rt}/${s.slice(5)}`;
        return s;
    }

    Process {
        id: finProc
        property int epoch: -1
        stdout: StdioCollector {
            id: finOut
            onStreamFinished: root._finStdout = text ?? ""
        }
        onRunningChanged: if (running) {
            epoch = root._epoch;
            root._finStdout = "";
        }
        onExited: code => {
            if (epoch !== root._epoch)
                return;
            const raw = ((root._finStdout ?? "").length > 0 ? root._finStdout : (finOut.text ?? "")).trim();
            console.warn(`[Dictation] finalizer exit ${code} len=${raw.length}`);
            if (code !== 0 || raw.length === 0) {
                if (code !== 0)
                    console.warn("[Dictation] finalizer exit", code, "— keeping raw segment");
                root._refineOrCommit(root._segText, root._segLang);
                return;
            }
            root._refineOrCommit(raw, root._segLang);
        }
    }

    Process {
        id: refineProc
        property int epoch: -1
        stdout: StdioCollector {
            id: refineOut
            onStreamFinished: root._refineStdout = text ?? ""
        }
        onRunningChanged: if (running) {
            epoch = root._epoch;
            root._refineStdout = "";
        }
        onExited: code => {
            if (epoch !== root._epoch)
                return;
            const raw = ((root._refineStdout ?? "").length > 0 ? root._refineStdout : (refineOut.text ?? "")).trim();
            console.warn(`[Dictation] refine exit ${code} len=${raw.length} fallback_len=${(root._refineFallback ?? "").length}`);
            if (code !== 0) {
                console.warn("[Dictation] refine failed, keeping raw");
                root._log({ event: "refine-failed", text: root._refineFallback });
                root._emitDone(root._refineFallback, root._refineLang, "raw");
                return;
            }
            let cleaned = "";
            let finishReason = "";
            try {
                const r = JSON.parse(raw);
                cleaned = (r?.choices?.[0]?.message?.content ?? "").trim();
                finishReason = r?.choices?.[0]?.finish_reason ?? "";
            } catch (e) {
                console.warn("[Dictation] refine parse failed, keeping raw");
            }
            // Truncation guard: a `length` stop means the tail is cut off —
            // committing it would silently lose dictation. Fall back to raw.
            if (finishReason === "length") {
                console.warn("[Dictation] refine truncated (finish_reason=length), keeping raw");
                root._log({ event: "refine-failed", reason: "truncated", text: root._refineFallback });
                root._emitDone(root._refineFallback, root._refineLang, "raw");
                return;
            }
            if (cleaned.length === 0) {
                root._emitDone(root._refineFallback, root._refineLang, "raw");
                return;
            }
            // Sanity guard. The main Refine job is DELETION (fillers,
            // stutters: "кот кот кот" -> "кот"), so a pure subset of the
            // input words is always accepted regardless of length ratio.
            // Only invented words are suspect: for short segments any of
            // them falls back to raw; for long ones a sane length ratio
            // still passes (word-form fixes).
            const fb = root._refineFallback ?? "";
            const fbWords = root._normalize(fb).split(" ").filter(w => w.length > 0);
            const clWords = root._normalize(cleaned).split(" ").filter(w => w.length > 0);
            const fbSet = {};
            for (const w of fbWords)
                fbSet[w] = true;
            let subset = clWords.length > 0;
            for (const w of clWords) {
                if (!fbSet[w]) {
                    subset = false;
                    break;
                }
            }
            if (!subset) {
                if (fb.length < 60 || cleaned.length < fb.length * 0.3 || cleaned.length > fb.length * 3 + 20) {
                    console.warn("[Dictation] refine invents words, keeping raw");
                    root._log({ event: "refine-failed", reason: "invented-words", text: fb });
                    root._emitDone(fb, root._refineLang, "raw");
                    return;
                }
            }
            root._emitDone(cleaned, root._refineLang, cleaned === fb ? "raw" : "refined");
        }
    }

    Process {
        id: logProc
        onExited: root._pumpLog()
    }
}
