import QtQuick
import Quickshell
import Quickshell.Io
import "../config"
import "AiModels.js" as AiModels

// AI backend (port of pShell services/Ai.qml): `scripts/ai/server.py` (uv
// script: httpx + g4f) listens on a per-session Unix socket in a private
// 0700 directory; every request is one connection from THIS process
// (services/AiRequest.qml, a Quickshell.Io Socket — no helper process).
// Access (server.py header): the kernel-reported peer must be this
// quickshell process (SO_PEERCRED), and each request carries the session
// token the server generated and printed on its stdout pipe (kept only in
// QML memory; never in argv / environ, which other processes of the user
// can read through /proc).
// Unlike pShell the server starts on the FIRST request (`ensure()`), not
// with the shell: uv + g4f cost ~100 MB of RAM nobody needs until then.
// Providers: OpenAI-compatible endpoints + Anthropic (keys in
// `ai.keysFile`, a chmod-600 JSON {"<keyId>": "<key>"}), Ollama (local,
// discovered once the server is up), g4f (keyless, flaky by nature).
// Users: the translator's "ai" engine (services/TranslateJob); a chat
// launcher plugin can reuse AiRequest the same way.
Scope {
    id: root

    readonly property var cfg: Config.data.ai ?? ({})

    // From the server's ready line (a new one per server run).
    property string sessionToken: ""
    // Per-session socket: a fixed path lets stale servers of earlier
    // sessions collide (server.py sweeps dead ones). Not a secret.
    readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp")
        + "/flicker-ai/flicker-ai-" + Math.random().toString(36).slice(2, 8) + ".sock"
    readonly property string keysPath: {
        const p = (root.cfg.keysFile ?? "~/.config/flicker/apikeys.json").trim();
        return p.startsWith("~/") ? `${Quickshell.env("HOME")}/${p.slice(2)}` : p;
    }

    // ── Server lifecycle ──────────────────────────────────────────────
    property bool wanted: false
    property bool serverReady: false

    // Start the server (no-op once it runs); requests wait for serverReady.
    function ensure(): void {
        root.wanted = true;
        if (!serverProc.running)
            serverProc.running = true;
    }

    Process {
        id: serverProc
        command: ["uv", "run", "--script", `${Quickshell.shellDir}/scripts/ai/server.py`]
        environment: ({
                "QS_AI_SOCKET": root.socketPath
            })
        stdout: SplitParser {
            onRead: line => {
                if (!line.startsWith("ready:"))
                    return;
                try {
                    root.sessionToken = JSON.parse(line.slice(6)).token ?? "";
                } catch (e) {
                    root.sessionToken = "";
                }
                root.serverReady = root.sessionToken !== "";
            }
        }
        stderr: SplitParser {
            onRead: line => {
                if (/error|traceback|refused/i.test(line))
                    console.warn("[Ai] server:", line);
            }
        }
        onExited: code => {
            root.serverReady = false;
            root.sessionToken = "";
            // Restart on an unexpected exit (it only stops with the shell).
            if (root.wanted) {
                console.warn("[Ai] server exited:", code, "— restarting");
                restartTimer.restart();
            }
        }
    }
    Timer {
        id: restartTimer
        interval: root.cfg.restartMs ?? 3000
        onTriggered: if (root.wanted) serverProc.running = true
    }

    // ── API keys (chmod-600 JSON, re-read on change) ──────────────────
    property var apiKeys: ({})
    FileView {
        id: keysFile
        path: root.keysPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.apiKeys = JSON.parse(text()) ?? {};
            } catch (e) {
                console.warn("[Ai] keys file unreadable:", e);
                root.apiKeys = {};
            }
        }
        onLoadFailed: root.apiKeys = {}
    }
    function getApiKey(provider: string): string {
        return root.apiKeys[provider] ?? "";
    }
    function setApiKey(provider: string, key: string): void {
        const updated = Object.assign({}, root.apiKeys, { [provider]: key });
        root.apiKeys = updated;
        keysFile.setText(JSON.stringify(updated, null, 2) + "\n");
        restrictKeys.running = true;
    }
    Process {
        id: restrictKeys
        command: ["chmod", "600", root.keysPath]
    }

    // ── Models ────────────────────────────────────────────────────────
    readonly property var builtinModels: AiModels.builtin
    property var ollamaModels: []
    property var g4fModels: []
    readonly property var allModels: root.builtinModels.concat(root.ollamaModels)

    // ai.model = an id from allModels, or "g4f/<model>" (keyless).
    function modelFor(id: string): var {
        const want = id || (root.cfg.model ?? "g4f/gpt-4");
        if (want.startsWith("g4f/")) {
            const name = want.slice(4);
            return { id: want, name: "G4F: " + name, model: name, format: "g4f", category: "free" };
        }
        return root.allModels.find(m => m.id === want) ?? root.builtinModels[0];
    }
    readonly property var currentModel: root.modelFor("")

    // Request object for AiRequest.send(), or { error } when it can't go.
    function chatRequest(messages: var, modelId: string): var {
        const model = root.modelFor(modelId ?? "");
        const apiKey = model.keyId ? root.getApiKey(model.keyId) : "";
        // An empty Bearer header is an httpx error, not a readable message.
        if (model.keyId && !apiKey)
            return { error: I18n.tr("No API key for \"%1\" in %2").arg(model.keyId).arg(root.cfg.keysFile ?? "~/.config/flicker/apikeys.json") };
        return {
            action: "chat",
            format: model.format,
            model: model.model ?? model.id,
            endpoint: model.endpoint ?? "",
            apiKey: apiKey,
            messages: messages,
            temperature: root.cfg.temperature ?? 0.7
        };
    }

    // Discovery: Ollama once the server is up (a local HTTP call); g4f only
    // on demand — its live list probes every keyless provider for real.
    onServerReadyChanged: if (root.serverReady) ollamaDiscover.send({ action: "models_ollama" })
    function discoverG4f(): void {
        root.ensure();
        g4fDiscover.send({ action: "models_g4f" });
    }
    AiRequest {
        id: ollamaDiscover
        ai: root
        onModels: list => root.ollamaModels = list.map(name => ({
                    id: "ollama/" + name,
                    name: name,
                    icon: "",
                    format: "openai",
                    keyId: null,
                    category: "local",
                    endpoint: "http://localhost:11434/v1/chat/completions",
                    model: name
                }))
    }
    AiRequest {
        id: g4fDiscover
        ai: root
        onModels: list => root.g4fModels = list.map(name => ({ id: "g4f/" + name, name: name }))
    }
}
