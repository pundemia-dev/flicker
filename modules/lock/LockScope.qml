import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// ext-session-lock lifecycle. All logic here; visuals in LockSkin.qml.
// Unlock handshake: beginUnlock() -> unlock signal -> skin plays exit anim ->
// finishUnlock(); fallback timer force-unlocks so a broken skin can't brick
// the session.
Scope {
    id: root

    readonly property alias locked: sessionLock.locked

    function activate(): void {
        sessionLock.locked = true;
    }

    WlSessionLock {
        id: sessionLock

        signal unlock

        function beginUnlock(): void {
            if (!locked)
                return;
            unlockFallback.restart();
            unlock();
        }

        function finishUnlock(): void {
            unlockFallback.stop();
            locked = false;
        }

        Variants {
            model: Quickshell.screens

            LockSurface {
                lock: sessionLock
                pam: pam
            }
        }
    }

    Pam {
        id: pam
        lock: sessionLock
    }

    Timer {
        id: unlockFallback
        interval: 3000
        onTriggered: sessionLock.locked = false
    }

    IpcHandler {
        target: "lock"
        // Deliberately no "toggle"/"unlock" over IPC: unlocking requires PAM
        // authentication. Only `activate` (lock) and `isLocked` are exposed.
        function activate(): void { root.activate(); }
        function isLocked(): bool { return sessionLock.locked; }
    }
}
