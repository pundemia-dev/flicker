import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// System updates (island module `updates`): the pending list and a run
// started from the island. The run lives in tmux (scripts/updates/update.sh
// — survives shell reloads, has a tty), the shell only tails its log:
// `poll` every `updates.pollMs` while it runs, once at start (picks up a run
// from before a reload). Root via pkexec → the island's polkit prompt.
//   repo  pacman -Syu (official repos)   all  yay -Syu (repos, then AUR)
// A question in the tty (pacman [Y/n], yay menus) = `prompt`; the module
// answers with send(). Nobody looking (`viewers` 0) → an event that opens
// the module, same on a failure / a kernel upgrade (reboot).
Scope {
    id: root
    property var events: null
    // services/PacmanWatch: a transaction started elsewhere (terminal) =
    // `pacman.busy` without an own run; the module then shows the tail of
    // /var/log/pacman.log (`externalLines`).
    property var pacman: null

    readonly property var cfg: Config.data.updates
    readonly property string script: Quickshell.shellDir + "/scripts/updates/update.sh"

    // [{ source: "repo"|"aur", name, from, to }]
    property var packages: []
    property bool checking: false
    property real checkedAt: 0
    // checkupdates failed (offline / mirrors): the count is unknown, not 0.
    property bool listError: false
    readonly property int repoCount: root.packages.filter(p => p.source === "repo").length
    readonly property int aurCount: root.packages.filter(p => p.source === "aur").length

    // idle | running | done | failed
    property string phase: "idle"
    property string mode: ""
    property int exitCode: 0
    property bool reboot: false
    property int pacnew: 0
    // Cleaned log lines (ANSI + carriage-return redraws resolved), last
    // `updates.logLines`.
    property var lines: []
    // "" | yesno | input — the run waits on its tty; promptText = that line.
    property string prompt: ""
    property string promptText: ""
    property bool promptDefaultYes: true
    // Open update modules (the module counts itself in / out).
    property int viewers: 0
    property var externalLines: []

    property real _lastSize: -1
    property string _promptRaw: ""
    property bool _starting: false

    function refresh(): void {
        if (!listProc.running)
            listProc.running = true;
    }
    // Refresh unless checked within `updates.recheckMs`.
    function refreshIfStale(): void {
        if (!root.checking && Date.now() - root.checkedAt > (root.cfg.recheckMs ?? 60000))
            root.refresh();
    }

    function start(m: string): void {
        if (root.phase === "running" || root._starting)
            return;
        root._starting = true;
        root.mode = m;
        root.lines = [];
        root.prompt = "";
        root.promptText = "";
        root._lastSize = -1;
        startProc.command = ["bash", root.script, "start", m];
        startProc.running = true;
    }

    // Types `keys` + Enter into the run's tty (prompt answer; "" = default).
    function send(keys: string): void {
        root.prompt = "";
        root.promptText = "";
        Quickshell.execDetached(["bash", root.script, "send", keys]);
        pollSoon.restart();
    }

    function openTerminal(): void {
        Quickshell.execDetached((Config.data.launcher?.apps?.terminal ?? ["kitty"]).concat(["bash", root.script, "attach"]));
    }

    // Forget a finished run: the module goes back to the list.
    function clear(): void {
        if (root.phase === "running")
            return;
        Quickshell.execDetached(["bash", root.script, "clear"]);
        root.phase = "idle";
        root.lines = [];
        root.prompt = "";
        root.promptText = "";
    }

    // ── Log parsing ──
    function clean(raw: string): var {
        const text = raw
            .replace(/\x1b\][^\x07\x1b]*(\x07|\x1b\\)/g, "")
            .replace(/\x1b\[[0-9;?]*[ -\/]*[@-~]/g, "")
            .replace(/\x1b[()][0-9A-Za-z]/g, "")
            .replace(/\x1b[=>78]/g, "")
            .replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "")
            .replace(/\r+\n/g, "\n");
        const out = [];
        for (const l of text.split("\n")) {
            // A redraw (progress bar) keeps its last non-empty frame.
            const frames = l.split("\r").filter(f => f.trim() !== "");
            const line = frames.length ? frames[frames.length - 1] : "";
            if (/^Script (started|done) on /.test(line))
                continue;
            out.push(line.replace(/\s+$/, ""));
        }
        // `text` ends with "\n" → the last element is "" (no partial line).
        return { lines: out, partial: text.endsWith("\n") ? "" : (out[out.length - 1] ?? "") };
    }

    function applyPoll(text: string): void {
        const cut = text.indexOf("\n---\n");
        const head = (cut >= 0 ? text.slice(0, cut) : text).split("\n");
        const body = cut >= 0 ? text.slice(cut + 5) : "";
        const status = (head.find(l => l.startsWith("status:")) ?? "").slice(7).trim();
        const alive = (head.find(l => l.startsWith("alive:")) ?? "").slice(6).trim() === "1";
        const size = parseFloat((head.find(l => l.startsWith("size:")) ?? "").slice(5)) || 0;
        const runMode = (head.find(l => l.startsWith("mode:")) ?? "").slice(5).trim();
        if (runMode !== "")
            root.mode = runMode;
        const parsed = root.clean(body);
        const all = parsed.lines;
        while (all.length && all[all.length - 1] === "")
            all.pop();
        // The tail may start mid-line: drop that first fragment.
        if (size > (root.cfg.logTailBytes ?? 16000) && all.length > 1)
            all.shift();
        // Reassigned only on a change: a new array every poll rebuilt the view.
        const shown = all.slice(-(root.cfg.logLines ?? 200));
        if (shown.join("\n") !== root.lines.join("\n"))
            root.lines = shown;

        const was = root.phase;
        if (status !== "") {
            const kv = {};
            for (const p of status.split(" ")) {
                const i = p.indexOf("=");
                if (i > 0)
                    kv[p.slice(0, i)] = p.slice(i + 1);
            }
            root.exitCode = parseInt(kv.exit ?? "1");
            root.reboot = kv.reboot === "1";
            root.pacnew = parseInt(kv.pacnew ?? "0") || 0;
            root.mode = kv.mode ?? root.mode;
            root.phase = root.exitCode === 0 ? "done" : "failed";
        } else if (alive) {
            root.phase = "running";
        } else if (body.length > 0 && !root._starting) {
            // Log without a status and no session: killed from outside.
            root.exitCode = -1;
            root.phase = "failed";
        } else if (!root._starting) {
            root.phase = "idle";
        }

        // Prompt: a yes/no question shows at once, any other partial line
        // (yay menus "==> ", provider "Enter a number …:") once the log
        // stood still for a poll — progress bars are partial lines too.
        const partial = root.phase === "running" ? parsed.partial.trim() : "";
        let p = "";
        if (/\[[Yy]\/[Nn]\]\s*$/.test(partial))
            p = "yesno";
        // A text password prompt (pkexec without the island's agent) is
        // never answered from here — the terminal only.
        else if (partial !== "" && size === root._lastSize && /(==>|[:?>])\s*$/.test(partial)
            && !/password|пароль/i.test(partial))
            p = "input";
        root._lastSize = size;
        const newPrompt = p !== "" && partial !== root._promptRaw;
        root._promptRaw = p !== "" ? partial : "";
        root.prompt = p;
        // A bare "==> " asks about the menu line above it: show that one.
        const strip = l => l.trim().replace(/^(::|==>)\s*/, "");
        let ask = p !== "" ? strip(partial) : "";
        for (let i = all.length - 2; p !== "" && ask === "" && i >= 0; i--)
            ask = strip(all[i]);
        root.promptText = ask;
        root.promptDefaultYes = !/\[y\/N\]/.test(partial);

        if (newPrompt && root.viewers === 0)
            root.notify("updates:ask", I18n.tr("Update needs an answer"), "qsBlue");
        if (was === "running" && root.phase !== "running") {
            root.refresh();
            if (root.phase === "failed" && root.viewers === 0)
                root.notify("updates:failed", I18n.tr("Update failed"), "accentRed");
            else if (root.phase === "done" && root.reboot)
                root.notify("updates:reboot", I18n.tr("Restart to finish the update"), "accentYellow");
        }
    }

    function notify(key: string, text: string, color: string): void {
        root.events?.post({
            key,
            glyph: "pacman",
            icon: String.fromCodePoint(0xf0baf),
            family: "nerd",
            color,
            text,
            open: "updates"
        });
    }

    Process {
        id: listProc
        command: ["bash", root.script, "list"]
        onStarted: root.checking = true
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                let failed = false;
                for (const l of this.text.split("\n")) {
                    const f = l.trim().split(/\s+/);
                    if (f[0] === "error")
                        failed = true;
                    else if (f.length >= 4)
                        out.push({ source: f[0], name: f[1], from: f[2], to: f[3] });
                }
                root.packages = out;
                root.listError = failed;
                root.checkedAt = Date.now();
                root.checking = false;
            }
        }
        onExited: root.checking = false
    }

    Process {
        id: startProc
        onExited: code => {
            root._starting = false;
            if (code === 0)
                root.phase = "running";
            pollProc.running = true;
        }
    }

    Process {
        id: pollProc
        command: ["bash", root.script, "poll"]
        environment: ({ LOG_TAIL: String(root.cfg.logTailBytes ?? 16000) })
        stdout: StdioCollector {
            onStreamFinished: root.applyPoll(this.text)
        }
    }

    Timer {
        running: root.phase === "running"
        repeat: true
        interval: root.cfg.pollMs ?? 700
        onTriggered: if (!pollProc.running) pollProc.running = true
    }
    // Right after an answer: the next output without waiting a full tick.
    Timer {
        id: pollSoon
        interval: 250
        onTriggered: if (!pollProc.running) pollProc.running = true
    }

    Process {
        id: externalProc
        command: ["tail", "-n", String(root.cfg.logLines ?? 200), "/var/log/pacman.log"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = this.text.replace(/\n$/, "").split("\n");
                if (l.join("\n") !== root.externalLines.join("\n"))
                    root.externalLines = l;
            }
        }
    }
    Timer {
        running: root.viewers > 0 && root.phase === "idle" && (root.pacman?.busy ?? false)
        repeat: true
        triggeredOnStart: true
        interval: root.cfg.pollMs ?? 700
        onTriggered: if (!externalProc.running) externalProc.running = true
    }

    // A module opening re-reads the run (cheap; idle otherwise never polls).
    onViewersChanged: if (root.viewers > 0 && root.phase !== "running" && !pollProc.running)
        pollProc.running = true

    Component.onCompleted: pollProc.running = true
}
