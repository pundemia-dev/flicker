import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Music recognition (iOS Control Center "Shazam"): scripts/shazam/
// recognize.py listens to what the computer plays (or the room when the
// output is silent, `source: "auto"`) and asks Shazam every `stepSec` up to
// `maxSec`. Phase idle | listening | found | none | error. While listening
// the bar shows a held event (pulsing Shazam glyph, "Listening…"); a match
// replaces it with the title and posts a notification (cover, tap = open
// on shazam.com, "Copy"). History (newest first, `historyLimit`) persists in
// statePath("shazam.json").
Scope {
    id: root
    required property var events

    readonly property var cfg: Config.data.shazam
    property string phase: "idle"
    // "monitor" | "mic": what the running session records right now.
    property string source: ""
    // Last match {title, artist, url, cover, album, year, at}.
    property var result: root.history[0] ?? null
    property var history: []
    readonly property bool listening: root.phase === "listening"
    // A cancelled run still delivers its buffered stdout: drop it.
    property bool cancelled: false

    function toggle(): void {
        if (root.listening)
            root.cancel();
        else
            root.start();
    }

    function start(): void {
        if (proc.running)
            return;
        root.cancelled = false;
        root.online = false;
        root.gotOutput = false;
        root.phase = "listening";
        root.source = "";
        settle.stop();
        root.announce(I18n.tr("Listening…"), true);
        proc.running = true;
    }

    function cancel(): void {
        if (!proc.running)
            return;
        root.cancelled = true;
        proc.signal(15);
        root.phase = "idle";
        root.events.cancel("shazam");
    }

    // One event key for the whole run: "Listening…" is held, the outcome
    // replaces it in place (the glyph stops breathing, pops on a match).
    function announce(text: string, hold: bool): void {
        if (!(Config.data.events.shazam ?? true))
            return;
        root.events.post({
            key: "shazam",
            glyph: "shazam",
            glyphArgs: { listening: hold, found: root.phase === "found" },
            icon: "\uedd6", // tabler brand-shazam (font fallback)
            color: "shazam",
            hold: hold,
            text: text
        });
    }

    function handle(line: string): void {
        if (root.cancelled)
            return;
        let m;
        try {
            m = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (m.state === "listening") {
            root.source = m.source ?? "";
        } else if (m.state === "found") {
            const r = { title: m.title, artist: m.artist, url: m.url, cover: m.cover, album: m.album, year: m.year, at: Date.now() };
            root.history = [r, ...root.history.filter(h => h.url !== r.url || r.url === "")].slice(0, root.cfg.historyLimit);
            root.save();
            root.finish("found");
            root.announce(root.short(r.title), false);
            root.notify(r);
        } else if (m.state === "none") {
            root.finish("none");
            root.announce(I18n.tr("No match"), false);
        } else if (m.state === "error") {
            console.warn("[Shazam]", m.message);
            root.finish("error");
            root.announce(I18n.tr("Failed"), false);
        }
    }

    function finish(phase: string): void {
        root.phase = phase;
        settle.restart();
    }

    // Event text: the title cut to eventMaxChars (no trimEnd() in QV4).
    function short(s: string): string {
        const max = root.cfg.eventMaxChars;
        return s.length > max ? s.slice(0, max - 1).replace(/\s+$/, "") + "…" : s;
    }

    function shq(s: string): string {
        return "'" + `${s}`.replace(/'/g, "'\\''") + "'";
    }

    // notify-send waits for the reply in the background: tap = default
    // action (open the track page), "Copy" = "Artist — Title".
    function notify(r: var): void {
        if (!root.cfg.notify)
            return;
        const line = r.artist ? `${r.artist} — ${r.title}` : r.title;
        const body = [r.artist, r.album].filter(s => !!s).join(" · ");
        const args = ["notify-send", "-a", "Shazam", "-i", r.cover || "audio-x-generic",
            "-A", "default=" + I18n.tr("Open"), "-A", "copy=" + I18n.tr("Copy"), r.title, body];
        Quickshell.execDetached(["bash", "-c",
            `a=$(${args.map(a => root.shq(a)).join(" ")}); `
            + `case "$a" in default) [ -n ${root.shq(r.url)} ] && xdg-open ${root.shq(r.url)};; `
            + `copy) printf %s ${root.shq(line)} | wl-copy;; esac`]);
    }

    function save(): void {
        stateFile.setText(JSON.stringify({ version: 1, history: root.history }));
    }

    // Offline first: online `uv run --script` re-resolves deps every start
    // (CaptureActions.uvScript); a silent offline failure (env not cached
    // yet) retries online once. uv itself is the process (no bash
    // wrapper): it forwards SIGTERM, python dies, parecord gets SIGPIPE.
    property bool online: false
    property bool gotOutput: false
    readonly property var command: ["uv", "run", "--quiet", ...(root.online ? [] : ["--offline"]),
        "--script", `${Quickshell.shellDir}/scripts/shazam/recognize.py`,
        "--source", root.cfg.source, "--step", `${root.cfg.stepSec}`, "--max", `${root.cfg.maxSec}`,
        "--cache", Quickshell.cachePath("shazam")]

    Process {
        id: proc
        command: root.command
        stdout: SplitParser {
            onRead: line => {
                root.gotOutput = true;
                root.handle(line);
            }
        }
        onExited: {
            if (root.listening && !root.cancelled && !root.gotOutput && !root.online) {
                root.online = true;
                proc.running = true;
                return;
            }
            if (root.listening && !root.cancelled) {
                root.finish("error");
                root.announce(I18n.tr("Failed"), false);
            }
        }
    }

    // found / none / error read on the card for a while, then idle again
    // (the card keeps the last match as its status).
    Timer {
        id: settle
        interval: root.cfg.statusHoldMs
        onTriggered: if (!root.listening) root.phase = "idle"
    }

    FileView {
        id: stateFile
        path: Quickshell.statePath("shazam.json")
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(stateFile.text());
                root.history = (s.history ?? []).filter(h => h && typeof h.title === "string");
            } catch (e) {
                console.warn("Shazam: bad state file, starting empty:", e);
            }
        }
    }
}
