import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Lyrics of the active MPRIS track (player module's lyrics panel) through
// scripts/lyrics/fetch.py: `lyrics.sources` in order — a local .lrc next
// to the track, lrclib.net, NetEase (synced), Genius (plain, last resort);
// synced lyrics win over plain whatever the source (see the script). urllib
// forced to IPv4 (the Weather/art `curl -4` reason); results cached in
// cachePath("lyrics"), misses for `lyrics.noneTtlSec`. Owned by services/Players.qml (`players.lyrics`)
// so the Island reads `shown` for the module size without extra wiring.
//
// Fetches only while the panel is shown (`shown` survives module close:
// reopening the player brings the panel back); a track change while shown
// is debounced — players publish title / artist / length one by one.
QtObject {
    id: root

    required property var players

    // Panel toggle (player module's lyrics button).
    property bool shown: false

    // idle | loading | ok | none | error
    property string status: "idle"
    // [{t: seconds (-1 = unsynced), x: text}], sorted by t.
    property var lines: []
    property bool synced: false
    property bool instrumental: false
    // Where the lines came from (local / lrclib / netease / genius).
    property string source: ""
    // Track the current `lines` belong to (stale lines never show for a
    // new track: the view checks it against `wantedKey`).
    property string loadedKey: ""

    readonly property var cfg: Config.data.lyrics ?? ({})
    readonly property real offset: (cfg.offsetMs ?? 0) / 1000

    readonly property var player: players.active
    readonly property string title: player?.trackTitle ?? ""
    readonly property string artist: player?.trackArtist ?? ""
    readonly property string album: player?.trackAlbum ?? ""
    readonly property real duration: (player?.lengthSupported ?? false) ? (player?.length ?? 0) : 0
    // Local track path (for a sibling .lrc), "" for streams.
    readonly property string file: {
        const url = player?.metadata?.["xesam:url"] ?? "";
        if (!url.startsWith("file://"))
            return "";
        try {
            return decodeURIComponent(url.slice(7));
        } catch (e) {
            return ""; // malformed %-escape
        }
    }
    readonly property string wantedKey: title === "" ? "" : `${artist}\n${title}\n${album}\n${Math.round(duration)}`
    readonly property bool current: loadedKey !== "" && loadedKey === wantedKey

    function toggle(): void {
        shown = !shown;
    }

    // Index of the line playing at `time` s (-1 before the first line).
    function indexForTime(time: real): int {
        const ls = root.lines;
        if (!root.synced || ls.length === 0)
            return -1;
        const target = time - root.offset + (root.cfg.leadSec ?? 0.15);
        let lo = 0;
        let hi = ls.length;
        while (lo < hi) {
            const mid = (lo + hi) >> 1;
            if (ls[mid].t <= target)
                lo = mid + 1;
            else
                hi = mid;
        }
        return lo - 1;
    }
    function timeForIndex(i: int): real {
        return i >= 0 && i < root.lines.length ? root.lines[i].t + root.offset : -1;
    }

    function reload(): void {
        if (!root.shown)
            return;
        if (root.wantedKey === "") {
            // Drop a pending / in-flight fetch: its late answer would turn
            // status back to "ok" for a track that is gone.
            debounce.stop();
            root._req += 1;
            root.status = "idle";
            return;
        }
        if (root.current && root.status === "ok")
            return;
        // Searching right away: the old track's none / error must not
        // flash for the new one during the debounce.
        if (!root.current)
            root.status = "loading";
        debounce.restart();
    }
    function retry(): void {
        root.loadedKey = "";
        root.reload();
    }

    onShownChanged: reload()
    onWantedKeyChanged: reload()

    property int _req: 0
    property Timer debounce: Timer {
        interval: root.cfg.debounceMs ?? 400
        onTriggered: root._fetch()
    }

    function _fetch(): void {
        const key = root.wantedKey;
        if (key === "")
            return;
        root._req += 1;
        root.status = "loading";
        fetchComp.createObject(root, {
            req: root._req,
            key: key,
            // --opt=VALUE: a title like "-1" or "- Intro -" would read as an option.
            command: ["python3", `${Quickshell.shellDir}/scripts/lyrics/fetch.py`,
                `--artist=${root.artist}`, `--title=${root.title}`, `--album=${root.album}`,
                `--duration=${root.duration}`, `--file=${root.file}`,
                `--sources=${(root.cfg.sources ?? ["local", "lrclib", "netease", "genius"]).join(",")}`,
                `--cache=${Quickshell.cachePath("lyrics")}`,
                `--timeout=${root.cfg.fetchTimeoutSec ?? 10}`,
                `--deadline=${root.cfg.deadlineSec ?? 30}`,
                `--none-ttl=${root.cfg.noneTtlSec ?? 43200}`]
        });
    }

    function _apply(req: int, key: string, code: int, text: string): void {
        if (req !== root._req)
            return;
        let res = null;
        if (code === 0) {
            try {
                res = JSON.parse(text);
            } catch (e) {
                console.warn("[Lyrics] parse:", e);
            }
        }
        if (!res) {
            root.status = "error";
            return;
        }
        root.loadedKey = key;
        if (res.status !== "ok") {
            root.lines = [];
            root.synced = false;
            root.instrumental = false;
            root.source = "";
            root.status = "none";
            return;
        }
        const ls = res.lines ?? [];
        // Long intro: an empty line at 0 s, the view shows its gap dots.
        if (res.synced === true && ls.length > 0 && ls[0].t >= (root.cfg.gapDotsSec ?? 4))
            ls.unshift({ t: 0, x: "" });
        root.lines = ls;
        root.synced = res.synced === true;
        root.instrumental = res.instrumental === true;
        root.source = res.source ?? "";
        root.status = root.instrumental || root.lines.length > 0 ? "ok" : "none";
    }

    property Component fetchComp: Component {
        Process {
            id: proc
            required property int req
            required property string key
            property string out: ""
            running: true
            stdout: StdioCollector {
                onStreamFinished: proc.out = text
            }
            stderr: StdioCollector {
                onStreamFinished: {
                    if (text.trim().length)
                        console.warn("[Lyrics]", text.trim());
                }
            }
            onExited: code => {
                // stdout's streamFinished may land after exited: read it late.
                Qt.callLater(() => {
                    root._apply(proc.req, proc.key, code, proc.out);
                    proc.destroy();
                });
            }
        }
    }
}
