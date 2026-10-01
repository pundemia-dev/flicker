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
    // Single-word fillers (normalized like segments): deletions of these
    // never count as lost content in the over-deletion guard below.
    property var fillerWords: ["э", "а", "м", "мм", "эм", "гм", "ммм", "ну", "вот", "типа", "um", "uh", "uhm", "er", "ah", "hmm"]
    // Conservative interjections for the RULES stage only: standalone tokens
    // that are never content. (Contextual fillers like ну/вот stay for the
    // LLM — "ну да" is real speech.)
    property var safeFillers: ["э", "м", "мм", "эм", "гм", "ммм", "хм", "хмм", "um", "uh", "uhm", "er", "ah", "hmm"]
    // Laughter survives the repeat collapser below.
    property var laughWords: ["ха", "аха", "хаха", "хе", "хехе", "lol", "лол"]
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

    // Deterministic pre-cleanup (no model): drops safe interjections and
    // collapses 4+ identical adjacent tokens ("я я я я" → first one).
    // Pairs stay ("очень очень" may be emphasis) — the gate below routes
    // them to LLM. Original token shapes kept, compare is normalized.
    function _applyRules(text: string): string {
        const words = (text ?? "").trim().split(/\s+/).filter(w => w.length > 0);
        const safe = {};
        for (const w of (root.safeFillers ?? []))
            safe[w] = true;
        const laugh = {};
        for (const w of (root.laughWords ?? []))
            laugh[w] = true;
        const kept = [];
        let run = [];
        let runNorm = "";
        const flush = () => {
            if (run.length === 0)
                return;
            if (run.length >= 4 && !laugh[runNorm])
                kept.push(run[0]);
            else
                for (const t of run)
                    kept.push(t);
            run = [];
            runNorm = "";
        };
        for (const raw of words) {
            const w = root._normalize(raw);
            if (w.length === 0)
                continue;
            if (safe[w])
                continue;
            if (run.length > 0 && w === runNorm) {
                run.push(raw);
                continue;
            }
            flush();
            run = [raw];
            runNorm = w;
        }
        flush();
        return kept.join(" ");
    }

    // Gate: LLM only on correction shapes. Comma shapes ("Марку, нет,
    // Ивану") checked on RAW text — _normalize strips commas. Bare
    // correction phrases ("то есть", "sorry") and adjacent duplicates
    // ("кот кот") on normalized. Plain negations ("не хочу") and short
    // interjections ("Нет.") pass through untouched — no delay.
    function _needsLLM(text: string): bool {
        const raw = text ?? "";
        const norm = root._normalize(raw);
        if (norm.length === 0)
            return false;
        const words = norm.split(" ").filter(w => w.length > 0);
        const hay = ` ${norm} `;
        const rlow = ` ${raw.toLowerCase()} `;
        if (rlow.indexOf(", нет") !== -1 || rlow.indexOf(", не ") !== -1
            || rlow.indexOf("нет,") !== -1 || rlow.indexOf("не,") !== -1)
            return true;
        for (let i = 1; i < words.length; i++) {
            if (words[i] === words[i - 1])
                return true;
        }
        if (words.length <= 2 && raw.indexOf(",") === -1)
            return false;
        for (const m of ["то есть", "точнее", "вернее", "то бишь", "ой", "sorry", "i mean", "actually", "pardon", "my bad"]) {
            if (hay.indexOf(` ${m} `) !== -1)
                return true;
        }
        return false;
    }

    function _refineOrCommit(text: string, lang: string): void {
        // Rules first (instant), LLM only when the gate sees correction
        // shapes. LLM failure falls back to the ruled text — still an
        // improvement over raw, and deterministic.
        const ruled = root._applyRules(text);
        if (!root._needsLLM(ruled)) {
            root._log({ event: "accepted", how: "ruled", text: ruled, lang: lang });
            root._emitDone(ruled, lang, "ruled");
            return;
        }
        if (root.refineEnabled) {
            root._refineFallback = ruled;
            root._refineLang = lang;
            // Output is a deletion of the input: cap tokens by input size
            // (Cyrillic ≈ 2-4 chars/token) instead of a fixed 256. The
            // truncation guard below still catches a `length` stop.
            const maxTok = Math.max(64, Math.min(512, Math.ceil(ruled.length / 2)));
            const payload = JSON.stringify({
                model: root.refineModel,
                messages: [
                    { role: "system", content: root.refinePrompt },
                    { role: "user", content: `<transcript>${ruled}</transcript>` }
                ],
                temperature: 0,
                max_tokens: maxTok
            });
            refineProc.command = ["curl", "-4", "-fsS", "--max-time", String(root.refineTimeoutS),
                "-X", "POST", root.refineUrl, "-H", "Content-Type: application/json",
                "--data-binary", payload];
            refineProc.running = true;
        } else {
            root._emitDone(ruled, lang, "raw");
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
            // Thinking-mode leakage (Gemma emits <|channel>thought...<channel|>
            // when reasoning slips on): strip thought blocks, keep the answer.
            // Preamble strip ("Вот очищенный текст:") + one wrapping-quote
            // layer. Whatever remains must survive the guards below.
            cleaned = root._stripDecor(cleaned);
            if (cleaned.length === 0) {
                root._emitDone(root._refineFallback, root._refineLang, "raw");
                return;
            }
            // Sanity guard. The main Refine job is DELETION (fillers,
            // stutters: "кот кот кот" -> "кот"), so a pure subset of the
            // input words is normally accepted regardless of length ratio.
            // But a subset with no lower bound summarizes ("Привет, как
            // дела, расскажи про погоду" -> "Привет"): over-deletion above
            // half the words falls back to raw, unless the dropped words
            // are repeats collapsing into kept words, or known fillers.
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
            } else {
                const fbC = {};
                for (const w of fbWords)
                    fbC[w] = (fbC[w] ?? 0) + 1;
                const clC = {};
                for (const w of clWords)
                    clC[w] = (clC[w] ?? 0) + 1;
                const fill = {};
                for (const w of (root.fillerWords ?? []))
                    fill[root._normalize(w)] = true;
                let lost = 0;
                for (const w in fbC) {
                    const del = fbC[w] - (clC[w] ?? 0);
                    if (del <= 0)
                        continue;
                    if (fill[w])
                        continue;
                    if ((clC[w] ?? 0) > 0)
                        continue;
                    lost += del;
                }
                if (fbWords.length > 0 && lost / fbWords.length > 0.5) {
                    console.warn("[Dictation] refine over-deletes, keeping raw");
                    root._log({ event: "refine-failed", reason: "over-deletion", text: fb });
                    root._emitDone(fb, root._refineLang, "raw");
                    return;
                }
            }
            // Script guard: Cyrillic must not come back Latin and vice versa
            // (a translate-instead-of-clean failure). Mixed inputs skip it.
            const fs = root._dominantScript(fb);
            const cs = root._dominantScript(cleaned);
            if ((fs === "cyr" && cs === "lat") || (fs === "lat" && cs === "cyr")) {
                console.warn("[Dictation] refine flips script, keeping raw");
                root._log({ event: "refine-failed", reason: "script-flip", text: fb });
                root._emitDone(fb, root._refineLang, "raw");
                return;
            }
            root._emitDone(cleaned, root._refineLang, cleaned === fb ? "raw" : "refined");
        }
    }

    // Strip model decor: thought-channel blocks (<|channel>thought ...
    // <channel|> per the Gemma template), bare think tokens, leading
    // "preamble:" intros in both languages, one wrapping quote layer.
    function _stripDecor(s: string): string {
        let t = (s ?? "").trim();
        t = t.replace(/<\|channel>thought[\s\S]*?<channel\|>/g, "").trim();
        t = t.replace(/<\/*\|?think\|?>/g, "").trim();
        for (let i = 0; i < 2; i++) {
            const before = t;
            t = t.replace(/^(вот очищенный текст|вот результат|вот исправленный вариант|исправленный текст|очищенный текст|результат|ответ|конечно|разумеется|here is|here's|the cleaned text|of course|sure|result|answer|transcript|translation)\s*[:\-—–]*\s*/i, "").trim();
            if (t === before)
                break;
        }
        const q = [["«", "»"], ["„", "“"], ["\"", "\""], ["'", "'"], ["‘", "’"]];
        for (const pair of q) {
            if (t.length >= 2 && t.startsWith(pair[0]) && t.endsWith(pair[1])) {
                t = t.slice(pair[0].length, t.length - pair[1].length).trim();
                break;
            }
        }
        return t;
    }

    // Dominant letter script: "cyr" | "lat" | "mix" (>60% wins) | "" (none).
    function _dominantScript(s: string): string {
        const t = s ?? "";
        const cyr = (t.match(/[а-яё]/gi) || []).length;
        const lat = (t.match(/[a-z]/gi) || []).length;
        const tot = cyr + lat;
        if (tot === 0)
            return "";
        if (cyr / tot > 0.6)
            return "cyr";
        if (lat / tot > 0.6)
            return "lat";
        return "mix";
    }

    Process {
        id: logProc
        onExited: root._pumpLog()
    }
}
