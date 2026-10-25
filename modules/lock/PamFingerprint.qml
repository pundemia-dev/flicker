import QtQuick
import Quickshell
import Quickshell.Services.Pam
import "../../config"

// Fingerprint half of the lock's PAM auth (Pam.qml owns the password half): its
// own PamContext (assets/pam.d/flicker-fprint, pam_fprintd only) listens next
// to the password one for as long as the lock is up. Match = `matched`.
// A miss rarely ends the PAM round: the T2 bridge (t2-touchid) reports it as
// "retry scan", so pam_fprintd only says "…again" and keeps listening. Every
// such message (or a "failed to match" one) = `failed` (the skin shakes like
// a wrong password). `fingerprintMaxFails` misses in a row abort the round and
// stop it until the next lock (the password still works) — kept below the
// T2 Secure Enclave's own limit (5 misses = Touch ID off until a macOS
// password login). A round that ends otherwise starts again after
// `fingerprintRetryMs`; a PAM error that comes at once (no reader, fprintd or
// the bridge down) stops it, one after a long listen is the round's timeout.
Scope {
    id: root

    required property var lock

    readonly property var cfg: Config.data.lock ?? ({})
    readonly property bool enabled: root.cfg.fingerprint ?? true
    readonly property bool listening: ctx.active
    property int fails: 0
    property bool stopped: true
    property real roundStart: 0

    signal matched
    signal failed

    function begin(): void {
        root.fails = 0;
        root.stopped = !root.enabled;
        if (!root.stopped)
            root.round();
    }

    function stop(): void {
        root.stopped = true;
        retry.stop();
        if (ctx.active)
            ctx.abort();
    }

    function round(): void {
        if (root.stopped || ctx.active)
            return;
        root.roundStart = Date.now();
        ctx.start();
    }

    function miss(): void {
        root.fails++;
        root.failed();
        if (root.fails >= (root.cfg.fingerprintMaxFails ?? 3))
            root.stop();
    }

    PamContext {
        id: ctx

        config: "flicker-fprint"
        configDirectory: Quickshell.shellDir + "/assets/pam.d"

        // pam_fprintd never asks for text; anything that does is not ours.
        onResponseRequiredChanged: if (responseRequired)
            abort()

        // pam_fprintd's own strings (English or translated): "…again" after a
        // retry scan, "Failed to match fingerprint" after a no-match. The
        // first prompt ("Place your finger…") matches neither.
        onPamMessage: if (!root.stopped && /again|failed to match|снова|ещё раз|еще раз|не удалось/i.test(message))
            root.miss()

        onCompleted: res => {
            if (root.stopped)
                return;
            if (res === PamResult.Success)
                return root.matched();
            // A no-match was already counted from its message.
            if (res === PamResult.Failed || res === PamResult.MaxTries)
                return retry.restart();
            // Error: a timed-out round listened for a while, a missing reader
            // answers at once.
            if (Date.now() - root.roundStart >= (root.cfg.fingerprintTimeoutMinMs ?? 10000))
                retry.restart();
            else
                root.stopped = true;
        }
    }

    Timer {
        id: retry
        interval: root.cfg.fingerprintRetryMs ?? 1200
        onTriggered: root.round()
    }
}
