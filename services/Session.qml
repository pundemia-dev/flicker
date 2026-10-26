import QtQuick
import Quickshell
import "../config"

// Session actions (modules/session): lock = the shell's own session lock,
// everything else a shell command from Config.session.commands
// (`logout` may be a map by compositor backend: niri / drift / hyprland /
// default). Runs `actionDelayMs` after the request so the island has
// closed first (no half-closed island in the lock / suspend frame).
Scope {
    id: root
    required property var lock
    required property var compositor

    property string pending: ""

    function run(id: string): void {
        root.pending = id;
        delay.restart();
    }

    function commandFor(id: string): string {
        const c = Config.data.session.commands ?? {};
        const cmd = c[id];
        if (cmd && typeof cmd === "object")
            return cmd[root.compositor?.detect?.backendName ?? ""] ?? cmd["default"] ?? "";
        return cmd ?? "";
    }

    function exec(id: string): void {
        if (id === "lock") {
            root.lock.activate(false);
            return;
        }
        const cmd = root.commandFor(id);
        if (cmd === "") {
            console.warn("Session: no command for", id);
            return;
        }
        // Lock before sleeping, so the machine wakes up locked; the lock
        // surface gets `lockSettleMs` to map before the system sleeps.
        if ((id === "suspend" || id === "hibernate") && (Config.data.session.lockOnSuspend ?? true)) {
            root.lock.expectSleep();
            root.lock.activate(false);
            const s = (Config.data.session.lockSettleMs ?? 600) / 1000;
            Quickshell.execDetached(["sh", "-c", `sleep ${s}; ${cmd}`]);
            return;
        }
        Quickshell.execDetached(["sh", "-c", cmd]);
    }

    Timer {
        id: delay
        interval: Config.data.session.actionDelayMs ?? 350
        onTriggered: {
            const id = root.pending;
            root.pending = "";
            root.exec(id);
        }
    }
}
