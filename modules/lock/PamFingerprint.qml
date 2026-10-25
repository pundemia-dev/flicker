import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import "../../config"

// Fingerprint half of the lock's PAM auth (Pam.qml owns the password half): its
// own PamContext (assets/pam.d/flicker-fprint, pam_fprintd only) listens next
// to the password one for as long as the lock is up. Match = `matched`.
// TEMP WORKAROUND (t2-touchid 0.1.0.r784: a wrong finger is a "retry scan",
// never verify-no-match). Remove when the bridge reports no-match: count
// misses from PamResult.Failed/MaxTries instead of parsing pam_fprintd's
// messages (onPamMessage) and drop `roundMissed`.
// A miss rarely ends the PAM round: the T2 bridge (t2-touchid) reports it as
// "retry scan", so pam_fprintd only says "…again" and keeps listening. Every
// such message (or a "failed to match" one) = `failed` (the skin shakes like
// a wrong password). `fingerprintMaxFails` misses in a row abort the round and
// give up until the next lock (the password still works) — kept below the
// T2 Secure Enclave's own limit (5 misses = Touch ID off until a macOS
// password login). A round that ended after a miss or after listening for a
// while (its timeout) starts again after `fingerprintRetryMs`.
//
// TEMP WORKAROUND (fprintd#216, fixed by fprintd MR !259). Remove when an
// fprintd release (> 1.94.5) contains !259 and a lid sleep with the lock up
// no longer jams it without scripts/lock/fprintd-resume-reset.service: drop
// the wake grace (`wokeAt`, fingerprintWakeGraceMs) and the idle wait
// (fingerprintIdleWaitMs) in onCompleted, and the unit. expectSleep() /
// the PrepareForSleep pause may stay (cheap), but are no longer required.
// A verify running when the system sleeps JAMS fprintd (fprintd#216, fix in
// fprintd MR !259, not merged as of Oct 2026): on PrepareForSleep fprintd
// suspends the device mid-verify ("Cannot run while suspended"), can then
// not close it ("still busy"), and every later Claim fails with "already
// been opened" (~85 ms PAM errors) until the fprintd PROCESS goes. Aborting
// on PrepareForSleep is too late (same signal) and logind sleeps ~50 ms after
// a lid close, so the lock cannot prevent it; the system-side fix restarts
// fprintd after every resume (fprintd-resume-reset.service, see AGENTS.md).
// The lock's part: no round from the session menu's Sleep (expectSleep())
// until the wake, a round aborted on PrepareForSleep true (any other sleep),
// and after the wake (PrepareForSleep false) quick retries for
// `fingerprintWakeGraceMs` — the first round can still hit the old fprintd
// while it restarts. Otherwise a round that fails at once without a miss
// (fprintd busy / re-activated / no reader) is retried with a doubling pause
// up to `fingerprintBackoffMaxMs`; from the 3rd one in a row the pause is at
// least `fingerprintIdleWaitMs` (fprintd exits idle — the only way out of the
// jam without the restart unit). Never given up: such errors are not misses,
// the SEP does not count them.
Scope {
    id: root

    required property var lock

    readonly property var cfg: Config.data.lock ?? ({})
    readonly property bool enabled: root.cfg.fingerprint ?? true
    readonly property bool listening: ctx.active
    // The lock is up (begin … stop).
    property bool engaged: false
    // Too many misses: password only until the next lock.
    property bool givenUp: false
    property bool stopped: true
    // Asleep / about to sleep: no round.
    property bool sleeping: false
    readonly property bool paused: root.sleeping
    // Last wake: quick retries for a while after it.
    property real wokeAt: 0
    // expectSleep() came before the lock was up.
    property bool holdForSleep: false
    property int fails: 0
    property int errors: 0
    property real roundStart: 0
    // This round said "…again" / "failed to match" (a real miss, not a fault).
    property bool roundMissed: false

    signal matched
    signal failed

    function begin(): void {
        root.engaged = true;
        root.givenUp = false;
        root.fails = 0;
        root.errors = 0;
        root.stopped = !root.enabled;
        root.sleeping = root.holdForSleep;
        root.holdForSleep = false;
        if (root.stopped || root.sleeping)
            return;
        // A sleep someone else started (idle action…) may already be on its
        // way: ask logind first.
        sleepQuery.running = false;
        sleepQuery.running = true;
    }

    // The lock is gone (unlocked, or a match).
    function stop(): void {
        root.engaged = false;
        root.sleeping = false;
        sleepHold.stop();
        root.halt();
    }

    function halt(): void {
        root.stopped = true;
        root.pauseRound();
    }
    function pauseRound(): void {
        retry.stop();
        if (ctx.active)
            ctx.abort();
    }

    function round(): void {
        if (root.stopped || root.paused || ctx.active)
            return;
        root.roundStart = Date.now();
        root.roundMissed = false;
        ctx.start();
    }

    function again(ms: real): void {
        retry.interval = Math.max(1, Math.round(ms));
        retry.restart();
    }

    function miss(): void {
        root.roundMissed = true;
        root.fails++;
        root.failed();
        if (root.fails >= (root.cfg.fingerprintMaxFails ?? 3)) {
            root.givenUp = true;
            root.halt();
        }
    }

    // ---- pauses ----

    // The session menu is about to suspend (LockScope.expectSleep).
    function expectSleep(): void {
        sleepHold.restart();
        if (!root.engaged) {
            root.holdForSleep = true;
            return;
        }
        root.sleeping = true;
        root.pauseRound();
    }
    function sleep(): void {
        if (!root.engaged)
            return;
        root.sleeping = true;
        root.pauseRound();
    }
    function wake(): void {
        sleepHold.stop();
        root.holdForSleep = false;
        root.wokeAt = Date.now();
        if (!root.sleeping)
            return;
        root.sleeping = false;
        root.resume();
    }
    function resume(): void {
        if (!root.engaged || root.givenUp || !root.enabled || root.paused)
            return;
        root.stopped = false;
        root.errors = 0;
        root.again(root.cfg.fingerprintResumeDelayMs ?? 1500);
    }

    // A suspend that never happened (failed / cancelled): listen again.
    Timer {
        id: sleepHold
        interval: root.cfg.fingerprintSleepHoldMs ?? 60000
        onTriggered: {
            root.holdForSleep = false;
            if (root.sleeping) {
                root.sleeping = false;
                root.resume();
            }
        }
    }

    // "(<true>,)" = the system is on its way to sleep: wait for the wake.
    Process {
        id: sleepQuery
        command: ["gdbus", "call", "--system", "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1",
            "--method", "org.freedesktop.DBus.Properties.Get", "org.freedesktop.login1.Manager", "PreparingForSleep"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.engaged || root.stopped)
                    return;
                if (/true/.test(this.text))
                    root.sleeping = true;
                else
                    root.round();
            }
        }
        // No logind / gdbus: just listen.
        onExited: code => {
            if (code !== 0 && root.engaged && !root.stopped && !root.paused)
                root.round();
        }
    }

    // dbus-monitor flushes every message (gdbus monitor did not through a
    // pipe): "signal … member=PrepareForSleep", then "   boolean true|false".
    Process {
        id: sleepWatch
        running: root.engaged && root.enabled
        command: ["dbus-monitor", "--system", "type='signal',sender='org.freedesktop.login1',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"]
        property bool next: false
        stdout: SplitParser {
            onRead: line => {
                if (/member=PrepareForSleep/.test(line)) {
                    sleepWatch.next = true;
                    return;
                }
                if (!sleepWatch.next)
                    return;
                sleepWatch.next = false;
                if (/boolean true/.test(line))
                    root.sleep();
                else if (/boolean false/.test(line))
                    root.wake();
            }
        }
    }

    PamContext {
        id: ctx

        config: "flicker-fprint"
        configDirectory: Quickshell.shellDir + "/assets/pam.d"

        // pam_fprintd never asks for text; anything that does is not ours.
        onResponseRequiredChanged: if (responseRequired)
            abort()

        // TEMP WORKAROUND (t2-touchid retry-scan misses, see the header).
        // pam_fprintd's own strings (English or translated): "…again" after a
        // retry scan, "Failed to match fingerprint" after a no-match. The
        // first prompt ("Place your finger…") matches neither.
        onPamMessage: if (!root.stopped && !root.paused && /again|failed to match|снова|ещё раз|еще раз|не удалось/i.test(message))
            root.miss()

        onCompleted: res => {
            if (root.stopped || root.paused)
                return;
            if (res === PamResult.Success)
                return root.matched();
            const base = root.cfg.fingerprintRetryMs ?? 1200;
            // A round that listened for a while (its timeout), or one a miss
            // ended (already counted from its message): the next one.
            if (Date.now() - root.roundStart >= (root.cfg.fingerprintTimeoutMinMs ?? 10000)
                    || ((res === PamResult.Failed || res === PamResult.MaxTries) && root.roundMissed)) {
                root.errors = 0;
                return root.again(base);
            }
            // Ended at once without a miss: a fault, not a finger. Right after
            // a wake fprintd is being restarted: try again soon. Otherwise
            // back off, and from the 3rd in a row give fprintd time to exit
            // idle (drops a jammed verify).
            root.errors++;
            // TEMP WORKAROUND (fprintd#216, see the header): wake grace + idle wait.
            if (Date.now() - root.wokeAt < (root.cfg.fingerprintWakeGraceMs ?? 10000))
                return root.again(base);
            let wait = Math.min(base * Math.pow(2, root.errors - 1), root.cfg.fingerprintBackoffMaxMs ?? 15000);
            if (root.errors >= 3)
                wait = Math.max(wait, root.cfg.fingerprintIdleWaitMs ?? 32000);
            root.again(wait);
        }
    }

    Timer {
        id: retry
        onTriggered: root.round()
    }
}
