import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../config"

// ext-session-lock lifecycle. All logic here; visuals in LockSkin.qml.
// Lock-in: every output is grabbed FIRST (grim PPM into the runtime dir), then
// the session locks — the skin's first frame is that grab, so locking shows
// no seam, and the skin dissolves what differs from the wallpaper
// (LockBackdrop). A grab that fails or exceeds `lock.grabTimeoutMs` locks
// anyway (security first; the skin then fades in from black).
// Unlock handshake: beginUnlock() -> unlock signal -> skin plays the reverse
// -> finishUnlock(); a fallback timer force-unlocks so a broken skin can't
// brick the session.
Scope {
    id: root

    readonly property alias locked: sessionLock.locked
    readonly property var cfg: Config.data.lock ?? ({})
    readonly property string shotDir: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/flicker/lock`
    // Grab of this lock (one stamp per lock); "" = locked without a grab.
    property string stamp: ""
    property bool grabbing: false
    // IslandRegistry (Shell): the island rect per output at lock time — the
    // password field starts there (LockField).
    property var registry: null
    // Keyboard pill on the lock (services/KeyboardIndicator + Theme, Shell).
    property var keyboard: null
    property var theme: null
    property var islandRects: ({})
    // services/Wallpaper: its `clock` (WallrClock) re-syncs a video wallpaper
    // after unlock (wallr falls behind under the lock).
    property var wallpaper: null

    function islandRect(name: string): var {
        return root.islandRects[name] ?? null;
    }

    function shq(s: string): string {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    function grabPath(name: string): string {
        return root.stamp === "" ? "" : `${root.shotDir}/grab-${name}-${root.stamp}.ppm`;
    }

    function activate(): void {
        if (sessionLock.locked || root.grabbing)
            return;
        // Snapshots for the animation only: whatever throws here must never
        // keep the session from locking.
        try {
            const rects = {};
            for (const i of root.registry?.islands ?? []) {
                const r = i?.lockRect?.();
                if (r?.visible && i.screen?.name)
                    rects[i.screen.name] = r;
            }
            root.islandRects = rects;
        } catch (e) {
            console.warn("[lock] preparing the lock animation failed:", e);
        }
        if (!(root.cfg.dissolve ?? true)) {
            root.stamp = "";
            sessionLock.locked = true;
            return;
        }
        root.stamp = Date.now().toString();
        root.grabbing = true;
        const dir = root.shq(root.shotDir);
        // With the grab: wallr's video position (regions.sh extracts that
        // frame of a video wallpaper as the lock's background).
        const ctl = root.shq(Quickshell.shellDir + "/scripts/wallpapers/wallrctl.sh");
        const shots = Quickshell.screens.map(s => `grim -t ppm -o ${root.shq(s.name)} ${root.shq(root.grabPath(s.name))} & `
            + `${ctl} pos ${root.shq(s.name)} > ${root.shq(root.grabPath(s.name).replace(/\.ppm$/, ".pos"))} &`).join(" ");
        grabProc.command = ["bash", "-c", `mkdir -p ${dir} && chmod 700 ${dir} && rm -f ${dir}/grab-* ; ${shots} wait`];
        grabProc.running = true;
        grabTimeout.restart();
    }

    function engage(ok: bool): void {
        if (!root.grabbing)
            return;
        root.grabbing = false;
        grabTimeout.stop();
        if (!ok)
            root.stamp = "";
        sessionLock.locked = true;
    }

    Process {
        id: grabProc
        onExited: code => root.engage(code === 0)
    }

    Timer {
        id: grabTimeout
        interval: root.cfg.grabTimeoutMs ?? 400
        onTriggered: {
            grabProc.running = false;
            root.engage(false);
        }
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

        // The grabs show screen contents: gone as soon as the lock is.
        onLockedChanged: if (!locked) {
            Quickshell.execDetached(["bash", "-c", `rm -f ${root.shq(root.shotDir)}/grab-*`]);
            root.wallpaper?.clock?.lockEnded();
        }

        // WlSessionLock instantiates this per screen itself (no Variants:
        // its modelData broke creation and aborted the lock -> black screen).
        LockSurface {
            lock: sessionLock
            pam: pamScope
            scope: root
        }
    }

    Pam {
        id: pamScope
        lock: sessionLock
    }

    Timer {
        id: unlockFallback
        interval: root.cfg.unlockFallbackMs ?? 4000
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
