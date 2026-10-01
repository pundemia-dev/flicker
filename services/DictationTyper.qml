import QtQuick
import Quickshell
import Quickshell.Io

// DictationTyper: wtype-only text output (no clipboard path by decision).
// Keeps `typedText` = what is currently on screen at the cursor and converges
// it to each applyText() target: common prefix is kept, the diverged tail is
// erased with BackSpace presses, the new suffix is typed. Partial updates
// that arrive while wtype runs coalesce into one follow-up run, so a fast
// streamer never overlaps two wtype processes. With typeEnabled false the
// state still converges (dry-run for headless tests) but no process spawns.
Item {
    id: root

    property int typeDelayMs: 0
    property bool typeEnabled: true
    property string typedText: ""
    property bool busy: typeProc.running
    property string lastError: ""

    signal failed(string message)

    property string _target: ""
    property string _sent: ""

    function applyText(full: string): void {
        root._target = full ?? "";
        if (!typeProc.running)
            root._pump();
    }

    function reset(): void {
        root._target = "";
        root._sent = "";
        root.typedText = "";
        root.lastError = "";
    }

    function eraseAll(): void {
        root.applyText("");
    }

    function _pump(): void {
        if (typeProc.running)
            return;
        if (root._target === root.typedText)
            return;
        const cur = Array.from(root.typedText);
        const want = Array.from(root._target);
        let i = 0;
        const n = Math.min(cur.length, want.length);
        while (i < n && cur[i] === want[i])
            i++;
        const backs = cur.length - i;
        const suffix = want.slice(i).join("");
        if (backs === 0 && suffix.length === 0)
            return;
        if (!root.typeEnabled) {
            root.typedText = root._target;
            return;
        }
        const args = [];
        for (let k = 0; k < backs; k++)
            args.push("-k", "BackSpace");
        if (root.typeDelayMs > 0)
            args.push("-d", String(root.typeDelayMs));
        if (suffix.length > 0)
            args.push("--", suffix);
        root._sent = root._target;
        typeProc.command = ["wtype"].concat(args);
        typeProc.running = true;
    }

    Process {
        id: typeProc
        stderr: StdioCollector {
            id: typeErr
        }
        onExited: code => {
            if (code !== 0) {
                const msg = `wtype exit ${code}: ${typeErr.text.trim()}`;
                root.lastError = msg;
                root.failed(msg);
                // Drop the failed target so we never loop on it; the screen
                // keeps whatever was typed before this run.
                // KNOWN LIMITS: a mid-run wtype failure may leave the screen
                // partially typed (typedText desyncs — the session fails
                // loudly rather than typing on top of unknown state), and a
                // focus/cursor move mid-dictation sends BackSpace to the
                // wrong place (needs a focus-loss guard from compositor
                // state — not wired).
                root._target = root.typedText;
                return;
            }
            root.typedText = root._sent;
            if (root._sent !== root._target)
                root._pump();
        }
    }
}
