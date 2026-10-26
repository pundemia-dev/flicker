import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import "../config"

// Idle chain (Oct 2026), inside the shell instead of hypridle / swayidle:
// dim → lock countdown → lock → screen off → sleep. Ideas taken from:
// caelestia (a list of IdleMonitors), DMS (AC / battery profiles, fade
// before the lock, gate on the shell's own inhibit state: a surface
// inhibitor stops counting while that surface is hidden — driftwm
// counts only inhibitors on screen — and a shorter screen-off while
// locked), noctalia (org.freedesktop.ScreenSaver + logind idle inhibitors,
// restore on re-arm), GNOME / KDE / macOS (dim the backlight itself, not an
// overlay; sleep waits while audio plays).
//
// Stages = seconds since the last input (`idle.ac` / `idle.battery`, 0 = off):
//   dim    built-in panel: backlight eased to dimLevel × the user's level
//          (scripts/idle/idled.py → logind SetBrightness: no process per
//          step; Brightness.held keeps it out of the saved level and the
//          OSD); other outputs: a black shade (core/IdleShade)
//   warn   the last lockWarnSec before the lock: an island event counts down
//   lock   LockScope.activate() (its grab sees the dim: the lock fades in
//          from exactly that frame)
//   off    backlight eased to 0 + shades to black, then DPMS (`idle.dpms`,
//          per compositor; wlopm on driftwm — without it the dark panel
//          stays the screen-off)
//   sleep  Session.exec(sleepAction), held back while `sleepBlockers`
// While locked, `lockedScreenOffSec` turns the screens off sooner, app
// inhibitors ignored (nobody watches a video behind the lock).
// Any input, or the chain becoming held, undoes dim / off at once.
//
// `holders` hold the WHOLE chain: Caffeine, app inhibitors (Wayland
// idle-inhibit is counted by the compositor itself and never shows up
// here; D-Bus ScreenSaver and systemd-inhibit --what=idle do), screen
// recording, dictation, the teleprompter (nobody types while reading),
// optionally a fullscreen window / playing media. `sleepBlockers` only keep
// the machine awake: playing media (`idle.media` "sleep") and the running
// statuses listed in `idle.sleepWaitsFor` (timer, pacman, downloads…).
//
// Sleep from elsewhere (lid, power key, systemctl suspend): logind
// PrepareForSleep → lock first (session.lockOnSuspend) while the helper's
// delay inhibitor holds the sleep back until the lock is up. `loginctl
// lock-session` locks too; LockedHint / IdleHint are kept in logind.
Scope {
    id: root

    required property var lock
    required property var session
    required property var brightness
    required property var caffeine
    required property var events
    property var players: null
    property var statuses: null
    property var recorder: null
    property var dictation: null
    property var prompter: null
    property var compositor: null

    // config.json may hold part of a group (a settings change writes one
    // key): every key falls back to these (= Config.qml defaults).
    readonly property var defaults: ({
            ac: { dimSec: 240, lockSec: 300, screenOffSec: 600, sleepSec: 0 },
            battery: { dimSec: 120, lockSec: 180, screenOffSec: 300, sleepSec: 900 },
            lockWarnSec: 10,
            lockedScreenOffSec: 30,
            sleepWaitsFor: ["timer", "recordSaving", "transcribe", "localSend", "pacman", "download", "modelDownload"],
            dpms: {
                niri: { off: "niri msg action power-off-monitors", on: "niri msg action power-on-monitors" },
                hyprland: { off: "hyprctl dispatch dpms off", on: "hyprctl dispatch dpms on" },
                "default": { off: "wlopm --off '*'", on: "wlopm --on '*'" }
            }
        })
    readonly property var cfg: Object.assign({}, root.defaults, Config.data.idle ?? {})
    readonly property bool enabled: root.cfg.enabled ?? true
    readonly property bool onBattery: UPower.onBattery
    readonly property var profile: {
        const src = root.onBattery ? "battery" : "ac";
        return Object.assign({}, root.defaults[src], root.cfg[src] ?? {});
    }

    readonly property real lockSec: Math.max(0, root.profile.lockSec ?? 0)
    // A dim at or after the lock would only dim the lock screen: dropped.
    readonly property real dimSec: {
        const d = root.profile.dimSec ?? 0;
        return d > 0 && (root.lockSec <= 0 || d < root.lockSec) ? d : 0;
    }
    readonly property real offSec: Math.max(0, root.profile.screenOffSec ?? 0)
    readonly property real sleepSec: Math.max(0, root.profile.sleepSec ?? 0)
    readonly property real lockedOffSec: Math.max(0, root.cfg.lockedScreenOffSec)
    readonly property int warnSec: root.lockSec > 0 ? Math.max(0, Math.min(root.cfg.lockWarnSec, root.lockSec - 1)) : 0

    // "" | "dim" | "off": what the screens show now.
    property string phase: ""
    property bool dpmsOff: false
    property int warnLeft: 0
    // org.freedesktop.ScreenSaver / systemd-inhibit holders (helper lines).
    property var screensaverHolders: []
    property var logindHolders: []
    property bool screensaverBusy: false

    readonly property var holders: {
        const h = [];
        const tr = s => I18n.tr(s);
        if (root.caffeine?.active)
            h.push({ kind: "caffeine", label: tr("Caffeine") });
        if (root.cfg.appInhibitors ?? true) {
            for (const i of root.screensaverHolders)
                h.push({ kind: "app", label: i.app || tr("An app"), reason: i.reason ?? "" });
            for (const i of root.logindHolders)
                h.push({ kind: "app", label: i.who || tr("An app"), reason: i.why ?? "" });
        }
        if (root.recorder?.recording)
            h.push({ kind: "recording", label: tr("Screen recording") });
        if (root.dictation?.active)
            h.push({ kind: "dictation", label: tr("Dictation") });
        if (root.prompter?.open && !root.prompter.paused)
            h.push({ kind: "prompter", label: tr("Teleprompter") });
        if ((root.cfg.fullscreen ?? false) && Quickshell.screens.some(s => root.compositor?.fullscreenOn(s.name)))
            h.push({ kind: "fullscreen", label: tr("Fullscreen window") });
        if ((root.cfg.media ?? "sleep") === "all" && root.players?.musicActive)
            h.push({ kind: "media", label: root.players.active?.identity || tr("Media") });
        return h;
    }
    readonly property bool held: root.holders.length > 0

    readonly property var sleepBlockers: {
        const b = [];
        if ((root.cfg.media ?? "sleep") !== "none" && root.players?.musicActive)
            b.push({ kind: "media", label: root.players.active?.identity || I18n.tr("Media") });
        const waits = root.cfg.sleepWaitsFor;
        for (const s of root.statuses?.items ?? [])
            if (waits.includes(s.key))
                b.push({ kind: "status", label: s.key });
        return b;
    }

    // Monitors run while this holds; rearm() drops it for one turn so every
    // timer starts over (new timeouts, after a wake, SimulateUserActivity).
    property bool gate: true
    readonly property bool armed: root.enabled && !root.held && root.gate

    function rearm(): void {
        root.gate = false;
        Qt.callLater(() => root.gate = true);
    }
    onLockSecChanged: rearm()
    onDimSecChanged: rearm()
    onOffSecChanged: rearm()
    onSleepSecChanged: rearm()
    onHeldChanged: if (root.held)
        root.wake()

    // --- screens ----------------------------------------------------------
    readonly property bool hasBacklight: root.brightness.initialized && root.brightness.deviceClass === "backlight"
    function backlit(name: string): bool {
        return root.hasBacklight && new RegExp(root.cfg.backlitOutputs ?? "^(eDP|LVDS|DSI)").test(name);
    }
    // core/IdleShade: target opacity + the time to get there.
    function shadeFor(name: string): real {
        if (root.phase === "off")
            return 1;
        if (root.phase === "dim" && !root.backlit(name))
            return 1 - (root.cfg.dimLevel ?? 0.3);
        return 0;
    }
    readonly property int shadeMs: root.phase === "off" ? (root.cfg.offFadeMs ?? 1500)
        : root.phase === "dim" ? (root.cfg.dimMs ?? 2000) : (root.cfg.undimMs ?? 250)

    function backlightTo(raw: int, ms: int): void {
        if (!root.hasBacklight)
            return;
        const b = root.brightness;
        if (!b.held) {
            b.held = true;
            root.send(`hold ${b.deviceClass} ${b.device} ${b.userRaw}`);
        }
        root.send(`ramp ${b.deviceClass} ${b.device} ${Math.round(raw)} ${ms}`);
    }

    function dim(): void {
        if (root.phase !== "")
            return;
        root.phase = "dim";
        root.send("idlehint 1");
        const b = root.brightness;
        const floor = Math.ceil(b.maxRaw * 0.02);
        root.backlightTo(Math.max(Math.min(floor, b.userRaw), Math.round(b.userRaw * (root.cfg.dimLevel ?? 0.3))), root.cfg.dimMs ?? 2000);
    }

    function screenOff(): void {
        if (root.phase === "off")
            return;
        root.phase = "off";
        root.cancelWarn();
        root.send("idlehint 1");
        root.backlightTo(0, root.cfg.offFadeMs ?? 1500);
        dpmsDelay.restart();
    }

    function wake(): void {
        root.cancelWarn();
        dpmsDelay.stop();
        if (root.phase === "")
            return;
        root.phase = "";
        root.send("idlehint 0");
        if (root.dpmsOff) {
            root.dpmsOff = false;
            root.dpms("on");
        }
        if (root.brightness.held)
            root.send(`ramp ${root.brightness.deviceClass} ${root.brightness.device} ${root.brightness.userRaw} ${root.cfg.undimMs ?? 250}`);
    }

    function dpms(what: string): void {
        const map = root.cfg.dpms;
        const be = map[root.compositor?.detect?.backendName ?? ""] ?? map["default"] ?? {};
        const cmd = be[what] ?? "";
        if (cmd === "")
            return;
        dpmsProc.command = ["sh", "-c", cmd];
        dpmsProc.running = true;
    }

    Timer {
        id: dpmsDelay
        interval: (root.cfg.offFadeMs ?? 1500) + 100
        onTriggered: if (root.phase === "off") {
            root.dpmsOff = true;
            root.dpms("off");
        }
    }

    property bool dpmsWarned: false
    Process {
        id: dpmsProc
        onExited: code => {
            if (code !== 0 && !root.dpmsWarned) {
                root.dpmsWarned = true;
                console.warn("[idle] screen-off command failed (exit", code + "):", dpmsProc.command[2],
                    "— the dimmed backlight stays the screen-off. On driftwm: pacman -S wlopm");
            }
        }
    }

    // --- lock countdown ---------------------------------------------------
    function startWarn(): void {
        if (root.lock.locked || root.warnSec <= 0)
            return;
        root.warnLeft = root.warnSec;
        warnTick.restart();
        root.events.post({
            key: "idle:lock",
            glyph: "lock",
            icon: "\ueae2", // tabler lock (font fallback)
            color: "islandFg",
            hold: true,
            text: () => I18n.tr("Locking in %1 s").arg(root.warnLeft)
        });
    }
    function cancelWarn(): void {
        if (!warnTick.running && root.warnLeft === 0)
            return;
        warnTick.stop();
        root.warnLeft = 0;
        root.events.cancel("idle:lock");
    }
    Timer {
        id: warnTick
        interval: 1000
        repeat: true
        onTriggered: root.warnLeft = Math.max(1, root.warnLeft - 1)
    }

    function idleLock(): void {
        root.cancelWarn();
        if (!root.lock.locked) {
            console.log("[idle] locking after", root.lockSec, "s idle");
            root.lock.activate(false);
        }
    }

    // --- sleep ------------------------------------------------------------
    readonly property bool sleepDue: sleepMon.isIdle && root.sleepBlockers.length === 0
    onSleepDueChanged: if (root.sleepDue) {
        console.log("[idle] sleeping after", root.sleepSec, "s idle");
        root.session.exec(root.cfg.sleepAction ?? "suspend");
    }
    onSleepBlockersChanged: if (sleepMon.isIdle && root.sleepBlockers.length > 0)
        console.log("[idle] sleep waits for", root.sleepBlockers.map(b => b.label).join(", "))

    // logind is about to sleep (any cause): lock first, then let it go —
    // only once every output SHOWS the lock's final frame (DMS lockerReady:
    // secure + rendered). Released at "locked", the system froze mid lock
    // animation, whose first frames are the desktop grab: the wake showed
    // the desktop for seconds. Not locked yet = the quick lock (no grab).
    // Already locking (session menu Sleep) = wait for its animation to end.
    property bool releasePending: false
    // logind PrepareForSleep(false): back from suspend (NightLight re-sends).
    signal resumed
    function prepareSleep(going: bool): void {
        if (!going) {
            root.resumed();
            root.releasePending = false;
            releaseFallback.stop();
            settle.stop();
            root.wake();
            root.rearm();
            return;
        }
        if (!root.lock.locked && !root.lock.grabbing && !(Config.data.session.lockOnSuspend ?? true)) {
            root.send("release");
            return;
        }
        root.releasePending = true;
        root.sleepAt = Date.now();
        releaseFallback.restart();
        if (!root.lock.locked && !root.lock.grabbing) {
            root.lock.expectSleep();
            root.lock.activate(true);
        }
        if (root.lock.settled)
            settle.restart();
    }
    property real sleepAt: 0
    function release(): void {
        if (!root.releasePending)
            return;
        console.log("[idle] sleep released after", Date.now() - root.sleepAt, "ms, lock settled:", root.lock.settled);
        root.releasePending = false;
        releaseFallback.stop();
        root.send("release");
    }
    // logind waits InhibitDelayMaxSec (5 s) for us at most anyway.
    Timer {
        id: releaseFallback
        interval: root.cfg.sleepLockWaitMs ?? 4500
        onTriggered: {
            console.warn("[idle] lock not up before sleep — letting it sleep anyway");
            root.release();
        }
    }
    // The settled frame still has to reach the panel before the freeze.
    Timer {
        id: settle
        interval: root.cfg.sleepSettleMs ?? 150
        onTriggered: root.release()
    }
    Connections {
        target: root.lock
        function onLockedChanged(): void {
            root.send(`lockedhint ${root.lock.locked ? 1 : 0}`);
            root.send(`active ${root.lock.locked ? 1 : 0}`);
            if (root.lock.locked)
                root.cancelWarn();
        }
        function onSettledChanged(): void {
            if (root.lock.settled && root.releasePending)
                settle.restart();
        }
    }

    // --- monitors ---------------------------------------------------------
    component Stage: IdleMonitor {
        required property real after
        enabled: root.armed && after > 0
        timeout: Math.max(1, after)
        respectInhibitors: root.cfg.appInhibitors ?? true
    }
    Stage {
        after: root.dimSec
        onIsIdleChanged: isIdle ? root.dim() : root.wake()
    }
    Stage {
        after: root.warnSec > 0 ? root.lockSec - root.warnSec : 0
        onIsIdleChanged: isIdle ? root.startWarn() : root.wake()
    }
    Stage {
        after: root.lockSec
        onIsIdleChanged: isIdle ? root.idleLock() : root.wake()
    }
    Stage {
        after: root.offSec
        onIsIdleChanged: isIdle ? root.screenOff() : root.wake()
    }
    Stage {
        id: sleepMon
        after: root.sleepSec
        onIsIdleChanged: if (!isIdle)
            root.wake()
    }
    // Locked: screens off sooner, whatever apps ask for (Caffeine still
    // holds it).
    IdleMonitor {
        enabled: root.enabled && root.gate && root.lock.locked && root.lockedOffSec > 0 && !root.caffeine?.active
        timeout: Math.max(1, root.lockedOffSec)
        respectInhibitors: false
        onIsIdleChanged: isIdle ? root.screenOff() : root.wake()
    }

    // --- helper -----------------------------------------------------------
    function send(line: string): void {
        if (helper.running)
            helper.write(line + "\n");
    }
    function onHelperLine(line: string): void {
        const sp = line.indexOf(" ");
        const cmd = sp < 0 ? line : line.slice(0, sp);
        const arg = sp < 0 ? "" : line.slice(sp + 1);
        switch (cmd) {
        case "ready":
            root.send(`lockedhint ${root.lock.locked ? 1 : 0}`);
            root.send(`active ${root.lock.locked ? 1 : 0}`);
            break;
        case "screensaver":
            if (arg === "busy") {
                root.screensaverBusy = true;
                console.warn("[idle] org.freedesktop.ScreenSaver is owned by another program: its inhibitors are not seen");
            } else {
                root.screensaverHolders = JSON.parse(arg);
            }
            break;
        case "logind":
            root.logindHolders = JSON.parse(arg);
            break;
        case "sleep":
            root.prepareSleep(arg === "1");
            break;
        case "lock":
            if (root.cfg.logindLock ?? true)
                root.lock.activate(false);
            break;
        case "unlock":
            // Deliberately ignored: unlocking needs PAM (same as IPC).
            console.log("[idle] logind unlock request ignored");
            break;
        case "activity":
            root.wake();
            root.rearm();
            break;
        case "ramped":
            if (root.phase === "" && root.brightness.held) {
                root.send("unhold");
                root.brightness.quiet();
                root.brightness.held = false;
            }
            break;
        }
    }
    Process {
        id: helper
        running: true
        command: ["python3", Quickshell.shellDir + "/scripts/idle/idled.py"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.onHelperLine(line);
                } catch (e) {
                    console.warn("[idle] bad helper line:", line, e);
                }
            }
        }
        stderr: SplitParser {
            onRead: line => console.warn("[idle]", line)
        }
        onExited: code => {
            console.warn("[idle] helper exited", code, "— restarting in 5 s");
            // It put the backlight back on its way out.
            root.brightness.held = false;
            root.screensaverHolders = [];
            root.logindHolders = [];
            helperRestart.start();
        }
    }
    Timer {
        id: helperRestart
        interval: 5000
        onTriggered: helper.running = true
    }

    // For IPC `idle status` and settings.
    function state(): var {
        return {
            enabled: root.enabled,
            profile: root.onBattery ? "battery" : "ac",
            stages: { dim: root.dimSec, warn: root.warnSec, lock: root.lockSec, off: root.offSec, sleep: root.sleepSec, lockedOff: root.lockedOffSec },
            phase: root.phase,
            dpmsOff: root.dpmsOff,
            locked: root.lock.locked,
            holders: root.holders,
            sleepBlockers: root.sleepBlockers,
            screensaverBusy: root.screensaverBusy,
            caffeine: { active: root.caffeine?.active ?? false, until: root.caffeine?.until ?? 0 }
        };
    }

    IpcHandler {
        target: "idle"
        function status(): string { return JSON.stringify(root.state()); }
        // Caffeine: toggle (its default duration), on for <minutes> (0 =
        // until turned off), off.
        function caffeine(): void { root.caffeine.toggle(); }
        function caffeineFor(minutes: real): void { root.caffeine.setActive(true, minutes); }
        function caffeineOff(): void { root.caffeine.setActive(false, 0); }
        // Run a stage now (dim | warn | off): any input undoes it.
        function test(stage: string): void {
            if (stage === "dim")
                root.dim();
            else if (stage === "warn")
                root.startWarn();
            else if (stage === "off")
                root.screenOff();
        }
        function wake(): void { root.wake(); root.rearm(); }
    }
}
