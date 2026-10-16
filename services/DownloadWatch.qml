import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// In-progress downloads for the status drop (StatusFeeds `download`,
// `modelDownload`), polled through scripts/status/downloads.sh:
//   browser  partial files in `status.downloadsDir` ("" = the XDG download
//            dir): Firefox .part, Chromium .crdownload. Neither carries the
//            final size, so the drop spins; the text = name · bytes so far.
//            Finished (partial gone, final file there) → event "Downloaded"
//            + the name, tap = open the file.
//   models   weights fetched by the ML scripts (WhisperX, pyannote, …):
//            HF hub `*.incomplete`, torch hub `*.partial` under
//            `status.modelDirs`. Background work: no outcome event.
// Only partials touched within `downloadsFreshMin` count (a killed download
// leaves its partial behind).
Scope {
    id: root
    required property var events

    readonly property var cfg: Config.data.status
    readonly property string home: Quickshell.env("HOME") ?? ""
    function expand(p: string): string {
        return `${p ?? ""}`.replace(/^~/, root.home);
    }
    property string xdgDownload: root.home + "/Downloads"
    readonly property string browserDir: (root.cfg.downloadsDir ?? "") !== "" ? root.expand(root.cfg.downloadsDir) : root.xdgDownload
    readonly property var modelDirs: (root.cfg.modelDirs ?? ["~/.cache/huggingface/hub", "~/.cache/torch/hub"]).map(d => root.expand(d))
    readonly property bool enabled: (root.cfg.download ?? true) || (root.cfg.modelDownload ?? true)

    // [{path, name, size}]
    property var browser: []
    property var models: []
    readonly property bool browserActive: root.browser.length > 0
    readonly property bool modelActive: root.models.length > 0

    Process {
        running: true
        command: ["xdg-user-dir", "DOWNLOAD"]
        stdout: StdioCollector {
            onStreamFinished: {
                const d = this.text.trim();
                if (d.length && d !== root.home)
                    root.xdgDownload = d;
            }
        }
    }

    Timer {
        running: root.enabled
        repeat: true
        triggeredOnStart: true
        interval: root.browserActive || root.modelActive ? (root.cfg.downloadsBusyPollMs ?? 1000) : (root.cfg.downloadsPollMs ?? 3000)
        onTriggered: if (!poll.running) poll.running = true
    }

    Process {
        id: poll
        command: [Quickshell.shellDir + "/scripts/status/downloads.sh", String(root.cfg.downloadsFreshMin ?? 2), root.browserDir].concat(root.modelDirs)
        stdout: StdioCollector {
            onStreamFinished: root.parse(this.text)
        }
    }

    function parse(text: string): void {
        const b = [], m = [];
        for (const line of text.split("\n")) {
            const f = line.split("\t");
            if (f.length < 3)
                continue;
            const path = f.slice(2).join("\t");
            const item = { path, size: parseFloat(f[1]) || 0, name: f[0] === "b" ? root.finalName(path) : root.modelName(path) };
            (f[0] === "b" ? b : m).push(item);
        }
        // Browser partials that went away: finished or cancelled.
        if (Config.data.events.download ?? true)
            for (const old of root.browser)
                if (!b.find(x => x.path === old.path))
                    root.checkDone(old);
        root.browser = b;
        root.models = m;
    }

    function finalName(path: string): string {
        return path.slice(path.lastIndexOf("/") + 1).replace(/\.(part|crdownload)$/, "");
    }
    // .../models--org--name/blobs/<hash>.incomplete → name; torch → file.
    function modelName(path: string): string {
        const hf = path.match(/models--[^/]*--([^/]+)\//);
        if (hf)
            return hf[1];
        return path.slice(path.lastIndexOf("/") + 1).replace(/\.[0-9a-f]+\.partial$|\.partial$/, "");
    }

    function human(bytes: real): string {
        const units = ["B", "KB", "MB", "GB"];
        let i = 0, v = bytes;
        while (v >= 1000 && i < units.length - 1) {
            v /= 1000;
            i++;
        }
        return `${v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)} ${units[i]}`;
    }
    function shorten(s: string): string {
        const max = root.cfg.downloadsMaxChars ?? 22;
        return s.length > max ? s.slice(0, max - 1) + "…" : s;
    }
    // Live texts for the start events.
    function browserText(): string {
        const it = root.browser[0];
        if (!it)
            return "";
        const more = root.browser.length > 1 ? ` +${root.browser.length - 1}` : "";
        return `${root.shorten(it.name)}${more} · ${root.human(root.browser.reduce((a, x) => a + x.size, 0))}`;
    }
    function modelText(): string {
        const it = root.models[0];
        return it ? `${root.shorten(it.name)} · ${root.human(root.models.reduce((a, x) => a + x.size, 0))}` : "";
    }

    // A finished download = its final file exists (a cancelled one has none).
    property var doneQueue: []
    function checkDone(item: var): void {
        root.doneQueue = [...root.doneQueue, item];
        if (!doneProc.running)
            root.nextDone();
    }
    function nextDone(): void {
        if (!root.doneQueue.length)
            return;
        const item = root.doneQueue[0];
        root.doneQueue = root.doneQueue.slice(1);
        doneProc.item = item;
        doneProc.command = ["sh", "-c", "[ -s \"$1\" ] && echo yes; true", "done", root.browserDir + "/" + item.name];
        doneProc.running = true;
    }
    Process {
        id: doneProc
        property var item: null
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "yes" && doneProc.item)
                    root.announceDone(root.browserDir + "/" + doneProc.item.name, doneProc.item.name);
            }
        }
        onExited: Qt.callLater(root.nextDone)
    }

    // Also IPC `island eventDemo downloaded`.
    function announceDone(file: string, name: string): void {
        root.events.post({
            key: `download:${file}`,
            glyph: "transfer",
            glyphArgs: { progress: 1 },
            icon: "",
            color: "qsBlue",
            texts: [I18n.tr("Downloaded"), root.shorten(name)],
            tap: () => Quickshell.execDetached(["xdg-open", file])
        });
    }
}
