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
//   = "<file>.audioctl" + SIGUSR2, speed = "<file>.speedctl" + SIGUSR2 (from
//   that moment on: the segment restarts, record.sh re-times it), stop =
//   SIGINT (finalize + concat). `recording` drops at stop; the file is
//   assembled in the background (`saving`, re-timing can take a while).
Item {
    id: root

    readonly property var cfg: Config.data.recorder
    property bool recording: false
    property bool paused: false
    property string audio: "none"
    // Playback speed picked on the recording controls' ruler (reset per
    // recording); applied from the moment it settles (speedApplyMs).
    property real speed: 1
    property real appliedSpeed: 1
    // Stopped, record.sh still assembling the file.
    property bool saving: false
    // 0..1 while saving (record.sh "progress" lines), null = not known yet.
    property var saveProgress: null
    // "auto" default memory: the last audio choice, session-only.
    property string lastAudio: "none"
    property string file: ""
    property bool discardRequested: false
    // Region being recorded (RecordRegionOverlay): output name + the EXACT
    // crop in its physical px (after the even-size rounding). "" / null =
    // whole output or `-g` geometry, no overlay.
    property string regionOutput: ""
    property var regionCrop: null
    // Capture handed over a region (its overlay is fading out, the start
    // follows): the marker shows already, so the selection frame turns into it.
    property bool regionPending: false

    // Even sizes: yuv420p / h264 need them.
    function evenCrop(crop: var): var {
        return {
            x: crop.x,
            y: crop.y,
            width: Math.max(2, crop.width - crop.width % 2),
            height: Math.max(2, crop.height - crop.height % 2)
        };
    }

    function prepareRegion(output: string, crop: var): void {
        if (root.recording || recProc.running || !crop || output.length === 0)
            return;
        root.regionOutput = output;
        root.regionCrop = root.evenCrop(crop);
        root.regionPending = true;
        pendingGuard.restart();
    }
    // A handover that never started (capture cancelled meanwhile).
    Timer {
        id: pendingGuard
        interval: root.cfg.region?.pendingMaxMs ?? 3000
        onTriggered: root.regionPending = false
    }
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
    // output). audio: one of audioModes ("" = default). output + crop
    // ({x, y, width, height} in that output's physical px) record the whole
    // output and crop in ffmpeg instead of `-g`: driftwm 0.19 ignores the
    // offset of screencopy capture_output_region (region_loc is stored but
    // never applied) and always delivered the top-left corner.
    function start(region: string, audio: string, output: string, crop: var): void {
        if (root.recording)
            return;
        if (recProc.running) {
            root.regionPending = false;
            Quickshell.execDetached(["notify-send", "-a", "pillShell", I18n.tr("Still saving the previous recording")]);
            return;
        }
        const a = root.audioModes.includes(audio) ? audio : root.defaultAudio();
        root.audio = a;
        root.lastAudio = a;
        root.discardRequested = false;
        root.file = root.recordPath();
        const cmd = [`${Quickshell.shellDir}/scripts/capture/record.sh`, a, root.file];
        if (output.length > 0 && crop) {
            const c = root.evenCrop(crop);
            cmd.push("-o", output, "-F", `crop=${c.width}:${c.height}:${c.x}:${c.y}`);
            root.regionOutput = output;
            root.regionCrop = c;
        } else {
            root.regionOutput = "";
            root.regionCrop = null;
            if (region.length > 0)
                cmd.push("-g", region);
        }
        if (root.cfg.hwAccel && root.cfg.hwDevice)
            cmd.push("--hw", root.cfg.hwDevice);
        cmd.push("--max-fps", String(root.cfg.maxFps ?? 60));
        recProc.command = cmd;
        recProc.running = true;
        root.speed = 1;
        root.appliedSpeed = 1;
        root.recording = true;
        // After `recording`: the marker stays shown through the hand-over.
        root.regionPending = false;
        root.paused = false;
        root.pausedAccum = 0;
        root.startedAt = Date.now();
        root.elapsedSeconds = 0;
    }

    function stop(): void {
        if (!root.recording)
            return;
        root.finish();
    }

    // The plate / controls leave at once; record.sh keeps assembling.
    function finish(): void {
        speedApply.stop();
        root.recording = false;
        root.paused = false;
        root.saving = true;
        root.saveProgress = null;
        recProc.signal(2);
    }

    onSpeedChanged: if (root.recording)
        speedApply.restart()
    // Debounced: scrolling the ruler through values must not restart the
    // segment for each one.
    Timer {
        id: speedApply
        interval: root.cfg.speedApplyMs ?? 600
        onTriggered: {
            if (!root.recording || root.speed === root.appliedSpeed)
                return;
            root.appliedSpeed = root.speed;
            Quickshell.execDetached(["bash", "-c", `printf '%s' ${root.shq(String(root.speed))} > ${root.shq(root.file + ".speedctl")} && kill -USR2 ${recProc.processId}`]);
        }
    }

    // Stop AND delete the result.
    function discard(): void {
        if (!root.recording)
            return;
        root.discardRequested = true;
        // record.sh skips re-timing / assembly when this flag exists.
        Quickshell.execDetached(["bash", "-c", `: > ${root.shq(root.file + ".discard")}`]);
        root.finish();
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
        stdout: SplitParser {
            onRead: line => {
                if (root.saving && line.startsWith("progress "))
                    root.saveProgress = Math.max(0, Math.min(1, parseFloat(line.slice(9)) || 0));
            }
        }
        onExited: {
            root.saveProgress = null;
            const f = root.shq(root.file);
            const discard = root.discardRequested;
            root.recording = false;
            root.paused = false;
            root.saving = false;
            root.discardRequested = false;
            // One outcome (user): saved / failed = a notification (tap on
            // a saved one opens the file); discarded = nothing (the user
            // did it).
            if (discard)
                Quickshell.execDetached(["rm", "-f", root.file]);
            else
                Quickshell.execDetached(["bash", "-c", `if [ -s ${f} ]; then a=$(notify-send -a pillShell -A default=${root.shq(I18n.tr("Open"))} ${root.shq(I18n.tr("Recording saved"))} ${f}); [ "$a" = default ] && xdg-open ${f}; else notify-send -a pillShell ${root.shq(I18n.tr("Recording failed"))} ${root.shq(I18n.tr("wf-recorder exited without a file"))}; fi`]);
        }
    }

    Timer {
        interval: 250
        repeat: true
        running: root.recording && !root.paused
        onTriggered: root.elapsedSeconds = Math.floor((root.pausedAccum + Date.now() - root.startedAt) / 1000)
    }
}
