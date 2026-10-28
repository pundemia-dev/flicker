import QtQuick
import Quickshell
import Quickshell.Io
import "../config"
import "Languages.js" as Languages

// One translation (pShell TranslatorPage backends): engines google / deepl /
// duckduckgo = scripts/translator/translate.py (stdin JSON in, one JSON line
// out), "ai" = services/AiRequest with translator.aiPrompt (streams). run()
// restarts it; a newer run drops the older one's late result (`epoch`).
// DeepL-extension behaviour: text already in the target language (the
// engine reports the detected source) is translated once more into
// translator.secondTarget — `effectiveTarget` says which one it went to.
Scope {
    id: root
    // services/Translator (cfg + ai).
    required property var translator

    property string text: ""
    property string source: "auto"
    property string target: "en"
    property string engine: "google"

    property string result: ""
    property string detected: ""
    property string error: ""
    property string effectiveTarget: root.target
    property bool busy: false
    signal finished

    readonly property var cfg: root.translator.cfg
    property int epoch: 0
    property string reqText: ""
    property string reqTarget: ""

    function run(): void {
        root.epoch++;
        aiReq.abort();
        proc.running = false;
        root.error = "";
        const text = root.text;
        if (text.trim().length === 0) {
            root.result = "";
            root.detected = "";
            root.busy = false;
            return;
        }
        root.busy = true;
        root.go(text, root.target, true);
    }
    function abort(): void {
        root.epoch++;
        aiReq.abort();
        proc.running = false;
        root.busy = false;
    }

    // `retarget`: allowed to switch to secondTarget once.
    property bool retarget: true
    function go(text: string, target: string, retarget: bool): void {
        root.reqText = text;
        root.reqTarget = target;
        root.retarget = retarget;
        root.effectiveTarget = target;
        if (root.engine === "ai") {
            root.runAi(text, target);
        } else {
            proc.runEpoch = root.epoch;
            proc.buffer = "";
            proc.running = true;
        }
    }

    function landed(text: string, detected: string): void {
        const second = root.cfg.secondTarget ?? "";
        if (root.retarget && root.source === "auto" && detected !== ""
                && detected === root.reqTarget && second !== "" && second !== root.reqTarget) {
            root.detected = detected;
            root.go(root.reqText, second, false);
            return;
        }
        root.result = text;
        root.detected = detected;
        root.busy = false;
        root.finished();
    }
    function failedWith(message: string): void {
        root.error = message;
        root.busy = false;
        root.finished();
    }

    Process {
        id: proc
        property string buffer: ""
        property int runEpoch: 0
        command: ["python3", "-I", `${Quickshell.shellDir}/scripts/translator/translate.py`]
        stdinEnabled: true
        onStarted: write(JSON.stringify({
                engine: root.engine,
                source: root.source,
                target: root.reqTarget,
                text: root.reqText,
                apiKey: root.translator.ai?.getApiKey("deepl") ?? ""
            }) + "\n")
        stdout: SplitParser {
            onRead: line => {
                if (line)
                    proc.buffer = line;
            }
        }
        onExited: {
            if (proc.runEpoch !== root.epoch)
                return;
            let obj = null;
            try {
                obj = JSON.parse(proc.buffer);
            } catch (e) {
                root.failedWith(I18n.tr("Could not read the translation"));
                return;
            }
            if (obj.ok)
                root.landed(obj.text ?? "", (obj.detected ?? "").toLowerCase());
            else
                root.failedWith(obj.error ?? I18n.tr("Translation failed"));
        }
    }

    // ── AI ────────────────────────────────────────────────────────────
    property string aiText: ""
    // Reasoning models stream a <think> block first (server.py wraps it).
    function clean(t: string): string {
        return t.replace(/<think>[\s\S]*?(<\/think>|$)/g, "").trim();
    }
    function runAi(text: string, target: string): void {
        const from = root.source === "auto" ? "the source language (auto-detect)" : Languages.name(root.source);
        const prompt = (root.cfg.aiPrompt ?? "{{text-to-translate}}")
            .replace(/\{\{from-language\}\}/g, from)
            .replace(/\{\{to-language\}\}/g, Languages.name(target))
            .replace(/\{\{text-to-translate\}\}/g, text);
        const req = root.translator.ai.chatRequest([{ role: "user", content: prompt }], root.cfg.aiModel ?? "");
        if (req.error) {
            root.failedWith(req.error);
            return;
        }
        root.aiText = "";
        root.result = "";
        root.detected = "";
        aiReq.send(req);
    }
    AiRequest {
        id: aiReq
        ai: root.translator.ai
        // Streams: the result grows as it comes.
        onDelta: t => {
            root.aiText += t;
            root.result = root.clean(root.aiText);
        }
        onDone: {
            root.result = root.clean(root.aiText);
            root.busy = false;
            root.finished();
        }
        onFailed: message => root.failedWith(message)
    }
}
