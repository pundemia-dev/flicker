import QtQuick
import Quickshell
import Quickshell.Io
import "../config"
import "Languages.js" as Languages

// Translator (DeepL browser extension, shell-wide): select text anywhere →
// a pill with a translate button pops up next to it (modules/translator/
// SelectionOverlay, one per screen, the keyboard pill's look) → a click
// grows it into the translation panel (TranslatorPanel). The launcher
// plugin `!tr` (modules/launcher/plugins/translate) translates typed text
// with the same engines (services/TranslateJob).
//
// Selection = the Wayland PRIMARY selection: `wl-paste --primary --watch`
// prints a line per new offer (GTK4 re-offers on every step of a drag,
// verified). Nothing reports the mouse buttons, so a change maps a
// full-screen probe surface per output and WAITS for its wl_pointer.enter:
// while a button is held the client's implicit grab keeps the pointer, the
// enter arrives exactly at the release (verified on driftwm: enter at the
// button-up ms; an unheld pointer gets it ~17 ms after the map). The text is
// read only then (`wl-paste --primary`), so the pill shows for the final
// selection. Keyboard selection (Shift+arrows) = the pill under the text
// caret (services/Caret): no button was held (enter within
// `selection.heldMs`) AND the caret moved within `caretRecentMs` before the
// offer. Anything else goes under the pointer — kitty offers primary only
// AFTER the button-up (no held button) while its caret sits at the prompt.
// The same text again without a held button is ignored (apps re-offer the
// primary selection on a window focus change).
Scope {
    id: root
    required property var ai
    required property var caret
    required property var lock
    required property var registry
    required property var compositor

    readonly property var cfg: Config.data.translator ?? ({})
    readonly property var selCfg: root.cfg.selection ?? ({})
    readonly property bool selectionEnabled: root.selCfg.enabled ?? true

    readonly property string source: root.cfg.source ?? "auto"
    readonly property string target: root.cfg.target ?? "en"
    readonly property string engine: root.cfg.engine ?? "google"
    function setTarget(code: string): void {
        if (code && code !== "auto")
            Config.set("translator.target", code);
    }
    function setSource(code: string): void {
        Config.set("translator.source", code || "auto");
    }
    function setEngine(id: string): void {
        Config.set("translator.engine", id);
    }
    // Swap: a concrete source flips with the target; "auto" turns the
    // target into the detected language (pShell TranslatorPage.swap).
    function swapLanguages(detected: string): void {
        if (root.source !== "auto") {
            const t = root.source;
            root.setSource(root.target);
            root.setTarget(t);
        } else if (detected && detected !== root.target) {
            root.setTarget(detected);
        }
    }
    readonly property var languages: Languages.list
    readonly property var targets: Languages.targets()
    function languageName(code: string): string {
        return I18n.tr(Languages.name(code));
    }
    readonly property var engines: [
        { id: "google", name: "Google" },
        { id: "deepl", name: "DeepL" },
        { id: "ai", name: "AI" },
        { id: "duckduckgo", name: "DuckDuckGo" }
    ]
    function engineName(id: string): string {
        return root.engines.find(e => e.id === id)?.name ?? id;
    }

    // ── Pill / panel state (drawn by SelectionOverlay) ────────────────
    // {output, x, y, width, height}: the box the pill sits under.
    property var anchor: null
    property string text: ""
    property bool pillShown: false
    property bool pillHovered: false
    property int pillSerial: 0
    property bool panelOpen: false
    // The selection was in a text field (caret up) when the panel opened:
    // "replace" pastes the translation over it.
    property bool editable: false
    property int panelSerial: 0
    // Panel geometry source: the pill capsule (screen-local) it grows out
    // of, set by the overlay right before openPanel().
    property var growFrom: null

    // The panel's translation (one at a time).
    readonly property TranslateJob job: TranslateJob {
        translator: root
        source: root.source
        target: root.target
        engine: root.engine
    }
    // Language / engine change while the panel is up: translate again.
    readonly property string trigger: `${root.source}|${root.target}|${root.engine}`
    onTriggerChanged: if (root.panelOpen) root.job.run()

    function openPanel(): void {
        if (root.text.trim() === "" || !root.anchor)
            return;
        root.pillShown = false;
        pillTimer.stop();
        root.editable = root.caret?.active ?? false;
        root.panelSerial++;
        root.panelOpen = true;
        root.job.text = root.text;
        // A fresh panel never shows the previous translation meanwhile.
        root.job.result = "";
        root.job.detected = "";
        root.job.run();
    }
    function closePanel(): void {
        root.panelOpen = false;
        root.job.abort();
    }
    function hidePill(): void {
        root.pillShown = false;
        pillTimer.stop();
    }

    Timer {
        id: pillTimer
        interval: root.selCfg.showMs ?? 4000
        onTriggered: {
            if (root.pillHovered)
                restart();
            else
                root.pillShown = false;
        }
    }
    onPillHoveredChanged: if (!root.pillHovered && root.pillShown) pillTimer.restart()

    // Close everything on lock.
    Connections {
        target: root.lock
        function onLockedChanged(): void {
            if (root.lock.locked) {
                root.hidePill();
                root.closePanel();
                root.probing = false;
            }
        }
    }

    // ── Selection watch ───────────────────────────────────────────────
    readonly property bool watching: root.selectionEnabled
    onWatchingChanged: selWatch.running = root.watching
    Component.onCompleted: selWatch.running = root.watching
    Process {
        id: selWatch
        // `cat` drains the offer (an unread pipe would EPIPE the app);
        // CLIPBOARD_STATE: data | nil (cleared) | sensitive.
        command: ["bash", "-c", "exec -a flicker-selwatch wl-paste --primary --type text --watch sh -c 'cat >/dev/null; echo \"${CLIPBOARD_STATE:-data}\"'"]
        stdout: SplitParser {
            onRead: line => root.selectionChanged((line ?? "").trim())
        }
        onExited: code => {
            if (!root.watching)
                return;
            console.warn("[Translator] wl-paste --primary exited:", code, "— restarting");
            selRestart.restart();
        }
    }
    Timer {
        id: selRestart
        interval: root.selCfg.watchRestartMs ?? 3000
        onTriggered: if (root.watching) selWatch.running = true
    }

    function suppressed(): bool {
        return root.lock.locked || root.panelOpen || (root.registry?.takesKeyboard ?? false);
    }
    function ignoredApp(): bool {
        const app = root.caret?.focusedWin?.appId ?? "";
        return app !== "" && (root.selCfg.ignoreApps ?? []).includes(app);
    }

    function selectionChanged(state: string): void {
        if (state !== "data") {
            root.hidePill();
            return;
        }
        if (root.suppressed() || root.ignoredApp())
            return;
        // A drag offers on every step: one probe waits for the release.
        if (!root.probing) {
            root.offeredAt = Date.now();
            root.probe();
        }
    }

    // ── Pointer probe (see header) ────────────────────────────────────
    property bool probing: false
    property real probeStart: 0
    // Mapped per screen by SelectionOverlay while probing.
    function probe(): void {
        root.probeStart = Date.now();
        root.probing = true;
        probeEnd.restart();
    }
    property var pointer: null
    property bool heldButton: false
    property real caretMovedAt: 0
    property string caretKey: ""
    Connections {
        target: root.caret
        // Real moves only (the helper may report the same rect again).
        function onRectChanged(): void {
            const key = JSON.stringify(root.caret?.rect ?? null);
            if (key !== root.caretKey) {
                root.caretKey = key;
                root.caretMovedAt = Date.now();
            }
        }
    }
    property real offeredAt: 0
    function pointerSeen(output: string, x: real, y: real): void {
        if (!root.probing)
            return;
        root.probing = false;
        probeEnd.stop();
        root.pointer = { output: output, x: x, y: y };
        root.heldButton = Date.now() - root.probeStart > (root.selCfg.heldMs ?? 60);
        if (root.pendingDirect !== "")
            root.finishDirect();
        else
            readSel.running = true;
    }
    // A button held this long (or the pointer on no output of ours): drop it.
    Timer {
        id: probeEnd
        interval: root.selCfg.releaseTimeoutMs ?? 20000
        onTriggered: root.probing = false
    }

    Process {
        id: readSel
        command: ["sh", "-c", `wl-paste --primary --no-newline --type text 2>/dev/null | head -c ${root.selCfg.maxChars ?? 5000}`]
        stdout: StdioCollector {
            onStreamFinished: root.selectionRead(text ?? "")
        }
    }

    property string lastText: ""
    function selectionRead(t: string): void {
        if (root.suppressed())
            return;
        const trimmed = t.trim();
        // Something besides digits / ASCII punctuation (letters of any script).
        if (trimmed.length < (root.selCfg.minChars ?? 2) || !/[^\s0-9!-\/:-@\[-`{-~]/.test(trimmed))
            return;
        if (trimmed === root.lastText && !root.heldButton)
            return;
        root.lastText = trimmed;
        const byKeyboard = !root.heldButton && root.offeredAt - root.caretMovedAt < (root.selCfg.caretRecentMs ?? 500);
        root.showPill(trimmed, !byKeyboard);
    }

    function pointerAnchor(): var {
        const p = root.pointer;
        return p ? { output: p.output, x: p.x, y: p.y, width: 0, height: root.selCfg.pointerHeight ?? 22 } : null;
    }
    function showPill(t: string, byMouse: bool): void {
        const caretBox = root.caret?.anchor ?? null;
        const a = (!byMouse && caretBox) ? caretBox : (root.pointerAnchor() ?? caretBox);
        if (!a)
            return;
        root.text = t;
        root.anchor = a;
        root.pillSerial++;
        root.pillShown = true;
        pillTimer.restart();
    }

    // Panel straight away (IPC / a bind): text at the pointer (probe), or
    // at the focused output's centre when nothing reports it in time.
    property string pendingDirect: ""
    function translateDirect(t: string): void {
        const trimmed = (t ?? "").trim();
        if (trimmed === "" || root.lock.locked)
            return;
        root.pendingDirect = trimmed;
        root.pointer = null;
        root.probe();
        directWait.restart();
    }
    Timer {
        id: directWait
        interval: root.selCfg.directProbeMs ?? 300
        onTriggered: root.finishDirect()
    }
    function finishDirect(): void {
        directWait.stop();
        root.probing = false;
        probeEnd.stop();
        const t = root.pendingDirect;
        root.pendingDirect = "";
        if (t === "")
            return;
        let a = root.pointerAnchor();
        if (!a) {
            const out = root.compositor?.focusedOutput ?? "";
            const scr = Quickshell.screens.find(s => s.name === out) ?? Quickshell.screens[0];
            a = { output: scr?.name ?? "", x: (scr?.width ?? 0) / 2, y: (scr?.height ?? 0) / 3, width: 0, height: 0 };
        }
        root.hidePill();
        root.text = t;
        root.anchor = a;
        root.growFrom = null;
        root.closePanel();
        root.openPanel();
    }
    // The direct path reads the selection without the pill.
    Process {
        id: readDirect
        command: ["sh", "-c", `wl-paste --primary --no-newline --type text 2>/dev/null | head -c ${root.selCfg.maxChars ?? 5000}`]
        stdout: StdioCollector {
            onStreamFinished: root.translateDirect(text ?? "")
        }
    }

    // ── Panel actions ─────────────────────────────────────────────────
    function shq(s: string): string {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }
    function copy(t: string): void {
        if (t !== "")
            Quickshell.execDetached(["bash", "-c", `printf '%s' ${root.shq(t)} | wl-copy`]);
    }
    // Replace the selection in a text field: clipboard + Ctrl+V once the
    // panel gave the keyboard back.
    function replace(t: string): void {
        if (t === "")
            return;
        root.copy(t);
        root.closePanel();
        pasteDelay.restart();
    }
    Timer {
        id: pasteDelay
        interval: root.cfg.pasteDelayMs ?? 180
        onTriggered: pasteProc.running = true
    }
    Process {
        id: pasteProc
        command: ["sh", "-c", root.cfg.pasteCommand ?? "wtype -M ctrl v -m ctrl"]
    }

    IpcHandler {
        target: "translator"
        // Translate the current selection in the panel (a bind).
        function selection(): void { readDirect.running = true; }
        function text(s: string): void { root.translateDirect(s); }
        function close(): void {
            root.hidePill();
            root.closePanel();
        }
        function language(code: string): void { root.setTarget(code); }
        function engine(id: string): void { root.setEngine(id); }
        function status(): string {
            return JSON.stringify({
                watching: selWatch.running,
                probing: root.probing,
                pill: root.pillShown,
                panel: root.panelOpen,
                anchor: root.anchor,
                text: root.text.slice(0, 80),
                engine: root.engine,
                target: root.target,
                busy: root.job.busy,
                result: root.job.result.slice(0, 120),
                effectiveTarget: root.job.effectiveTarget,
                detected: root.job.detected,
                error: root.job.error
            });
        }
    }
}
