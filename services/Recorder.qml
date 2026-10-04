import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Screen recording: single source of truth for the recording process and
// the `recording` flag (drives the red clock plate). The compositor facade
// delegates startRecording/stopRecording here. The process is
// scripts/capture/record.sh (port of pShell's capture_record.sh):
//   audio none | system | mic | both ("both" mixes mic + system through a
//   temporary null sink); pause = segment split (SIGUSR1), live audio switch
//   = "<file>.audioctl" + SIGUSR2, stop = SIGINT (finalize + lossless concat).
Item {
    id: root

    readonly property var cfg: Config.data.recorder
    property bool recording: false
    property bool paused: false
    property string audio: "none"
    // "auto" default memory: the last audio choice, session-only.
    property string lastAudio: "none"
    property string file: ""
    property bool discardRequested: false
    // Elapsed = time before the current segment + time since it started.
    property double startedAt: 0
    property double pausedAccum: 0
    property int elapsedSeconds: 0
    readonly property bool canStop: recording
    readonly property var audioModes: ["none", "system", "mic", "both"]
    readonly property string elapsedText: {
        const m = Math.floor(elapsedSeconds / 60).toString().padStart(2, "0");
        const s = (elapsedSeconds % 60).toString().padStart(2, "0");
        return `${m}:${s}`;
    }

    function shq(s: string): string {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    // Audio preselected for a new recording ("auto" = last choice).
    function defaultAudio(): string {
        const def = root.cfg.audioDefault ?? "auto";
        return def === "auto" ? root.lastAudio : def;
    }

    function recordPath(): string {
        const home = Quickshell.env("HOME") ?? "";
        const raw = root.cfg.recordDir || "~/Videos";
        const dir = raw.startsWith("~") ? home + raw.slice(1) : raw;
        return `${dir}/recording_${Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH.mm.ss")}.mp4`;
    }

    // region: "x,y wxh" global logical geometry ("" = wf-recorder's default
    // output). audio: one of audioModes ("" = default).
    function start(region: string, audio: string): void {
        if (root.recording)
            return;
        const a = root.audioModes.includes(audio) ? audio : root.defaultAudio();
        root.audio = a;
        root.lastAudio = a;
        root.discardRequested = false;
        root.file = root.recordPath();
        const cmd = [`${Quickshell.shellDir}/scripts/capture/record.sh`, a, root.file];
        if (region.length > 0)
            cmd.push("-g", region);
        if (root.cfg.hwAccel && root.cfg.hwDevice)
            cmd.push("--hw", root.cfg.hwDevice);
        recProc.command = cmd;
        recProc.running = true;
        root.recording = true;
        root.paused = false;
        root.pausedAccum = 0;
        root.startedAt = Date.now();
        root.elapsedSeconds = 0;
    }

    function stop(): void {
        if (root.recording)
            recProc.signal(2);
    }

    // Stop AND delete the result.
    function discard(): void {
        if (!root.recording)
            return;
        root.discardRequested = true;
        recProc.signal(2);
    }

    function togglePause(): void {
        if (!root.recording)
            return;
        if (root.paused)
            root.startedAt = Date.now();
        else
            root.pausedAccum += Date.now() - root.startedAt;
        root.paused = !root.paused;
        recProc.signal(10);
    }

    function setAudio(a: string): void {
        if (a === root.audio || !root.audioModes.includes(a))
            return;
        root.audio = a;
        root.lastAudio = a;
        if (root.recording)
            Quickshell.execDetached(["bash", "-c", `printf '%s' ${root.shq(a)} > ${root.shq(root.file + ".audioctl")} && kill -USR2 ${recProc.processId}`]);
    }

    function cycleAudio(): void {
        root.setAudio(root.audioModes[(root.audioModes.indexOf(root.audio) + 1) % root.audioModes.length]);
    }

    Process {
        id: recProc
        onExited: {
            const f = root.shq(root.file);
            const discard = root.discardRequested;
            root.recording = false;
            root.paused = false;
            root.discardRequested = false;
            if (discard)
                Quickshell.execDetached(["bash", "-c", `rm -f ${f}; notify-send -a pillShell 'Запись удалена'`]);
            else
                Quickshell.execDetached(["bash", "-c", `[ -s ${f} ] && notify-send -a pillShell 'Запись сохранена' ${f} || notify-send -a pillShell 'Запись не удалась' 'wf-recorder завершился без файла'`]);
        }
    }

    Timer {
        interval: 250
        repeat: true
        running: root.recording && !root.paused
        onTriggered: root.elapsedSeconds = Math.floor((root.pausedAccum + Date.now() - root.startedAt) / 1000)
    }
}
