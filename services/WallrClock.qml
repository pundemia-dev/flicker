import QtQuick
import Quickshell
import Quickshell.Io

// wallr playback per output (child of services/Wallpaper): pause while a
// window is fullscreen there / on battery / in Low Power Mode, working around wallr 0.6.4's
// bugs (scripts/wallpapers/wallrctl.sh): a VIDEO paused > 5 s dies on a plain
// resume (its stall watchdog), so a long pause ends with a revive (re-set)
// seeked back to the position frozen at the pause; seek only after resume.
// Session lock: wallr keeps playing, but its picture can't advance while the
// lock hides its surface (Vulkan FIFO present blocks) and once unlocked it
// played the missed frames through (seconds of "fast forward"); a plain seek
// right at unlock KILLED it (the loop woke to a flushed decoder, last upload
// > 5 s old) → lockEnded() re-sets the video and seeks it to its own clock.
Scope {
    id: root

    required property var cfg
    required property var compositor
    property bool discharging: false
    // Low Power Mode with Config.powerSave.pauseVideo (services/Wallpaper).
    property bool powerSave: false
    readonly property string ctl: Quickshell.shellDir + "/scripts/wallpapers/wallrctl.sh"

    // Positions frozen by our pauses (s, per output): a revive seeks back.
    property var frozen: ({})

    function lockEnded(): void {
        for (const d of outputs.instances) {
            if (d.kind === "video") {
                d.needResync = true;
                d.sync();
            }
        }
    }

    Variants {
        id: outputs
        model: Quickshell.screens

        delegate: Scope {
            id: out
            required property ShellScreen modelData
            readonly property string name: out.modelData.name
            property string path: ""
            readonly property string kind: /\.(mp4|webm|mkv|mov|avi|m4v)$/i.test(out.path) ? "video"
                : /\.gif$/i.test(out.path) ? "animated" : "image"
            readonly property bool want: ((root.cfg.pauseOnFullscreen ?? true) && (root.compositor?.fullscreenOn(out.name) ?? false))
                || ((root.cfg.pauseOnBattery ?? false) && root.discharging)
                || root.powerSave
            // What wallr has from us ("unknown" until the start-up revive).
            // ONE process per output runs the commands strictly in order and
            // only the one needed to reach `want` — a pause racing a resume
            // in two processes (pause + position read is slower) left GIFs
            // paused after a quick fullscreen toggle, and a command sent
            // while the previous still ran was silently dropped.
            property string applied: "unknown"
            readonly property bool paused: out.applied === "paused"
            property real since: 0
            property bool needResync: false

            onWantChanged: out.sync()
            Component.onCompleted: out.sync()

            function sync(): void {
                if (proc.running)
                    return;
                if (out.want && out.applied !== "paused") {
                    out.since = Date.now();
                    out.run("paused", [root.ctl, "pause", out.name]);
                } else if (!out.want && out.applied === "unknown") {
                    // At start-up wallr may have sat paused (an earlier shell)
                    // for long already: revive in place ("here" = its frozen
                    // position) — a plain resume would kill a video.
                    out.run("playing", [root.ctl, "resume", out.name, "here", "1"]);
                } else if (!out.want && out.applied === "paused") {
                    const long = out.since > 0 && Date.now() - out.since > (root.cfg.wallrStallMs ?? 4000);
                    const pos = long ? root.frozen[out.name] : undefined;
                    out.needResync = false;
                    out.run("playing", [root.ctl, "resume", out.name, pos !== undefined ? Number(pos).toFixed(3) : "-", long ? "1" : "0"]);
                } else if (out.needResync && out.applied === "playing") {
                    out.needResync = false;
                    out.run("playing", [root.ctl, "resync", out.name, String((root.cfg.catchupLeadMs ?? 20) / 1000)]);
                }
            }
            property string pending: ""
            function run(state: string, cmd: var): void {
                out.pending = state;
                proc.command = cmd;
                proc.running = true;
            }
            function storeFrozen(text: string): void {
                const v = parseFloat(text);
                const f = Object.assign({}, root.frozen);
                if (isNaN(v))
                    delete f[out.name];
                else
                    f[out.name] = v;
                root.frozen = f;
            }

            Process {
                id: proc
                stdout: StdioCollector {
                    onStreamFinished: if (out.pending === "paused")
                        out.storeFrozen(text.trim())
                }
                onExited: {
                    out.applied = out.pending;
                    Qt.callLater(out.sync);
                }
            }
            FileView {
                path: Quickshell.env("HOME") + "/.cache/wallr/last_wallpaper/" + out.name
                watchChanges: true
                printErrors: false
                onFileChanged: reload()
                onLoaded: out.path = text().trim()
            }
        }
    }
}
