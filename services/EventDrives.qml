import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Event source: removable drives (USB sticks, SD cards, external disks;
// DriveGlyph). `udevadm monitor` (block subsystem) wakes a debounced
// `lsblk` re-read; a volume = a hotplug / removable block device with a
// filesystem. New volume -> event (label or model, then the size); tap =
// open it in the file manager, mounting it first through udisks when no
// automounter did. Removed -> the stick slides out. Present at start = no
// event.
Scope {
    id: root
    required property var events

    property var known: ({})
    property bool armed: false
    Timer {
        running: true
        interval: Config.data.events.startupQuietMs
        onTriggered: {
            root.armed = true;
            query.running = true;
        }
    }
    // Start-up state: `known` filled before arming (no events for it).
    Component.onCompleted: query.running = true

    Process {
        id: watch
        running: true
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=block"]
        stdout: SplitParser {
            onRead: line => {
                if (/\s(add|remove|change)\s/.test(line))
                    debounce.restart();
            }
        }
    }
    Timer {
        id: debounce
        interval: Config.data.events.drivesSettleMs ?? 700
        onTriggered: query.running = true
    }

    Process {
        id: query
        command: ["lsblk", "-J", "-b", "-o", "PATH,LABEL,MODEL,HOTPLUG,RM,FSTYPE,SIZE,TYPE"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(this.text)
        }
    }

    function parse(text: string): void {
        let tree = [];
        try {
            tree = JSON.parse(text).blockdevices ?? [];
        } catch (e) {
            return;
        }
        const now = {};
        const walk = (dev, parent) => {
            const hot = dev.hotplug === true || dev.rm === true || dev.hotplug === "1" || dev.rm === "1"
                || parent?.hot === true;
            const model = (dev.model ?? "") || (parent?.model ?? "");
            if (hot && dev.fstype && dev.type !== "loop" && dev.fstype !== "swap")
                now[dev.path] = { label: (dev.label ?? "") || model.trim() || I18n.tr("USB drive"), size: root.human(dev.size) };
            for (const c of dev.children ?? [])
                walk(c, { hot, model });
        };
        for (const d of tree)
            walk(d, null);
        if (root.armed && (Config.data.events.drives ?? true)) {
            for (const path in now)
                if (!root.known[path])
                    root.announce(path, now[path].label, now[path].size, true);
            for (const path in root.known)
                if (!now[path])
                    root.announce(path, root.known[path].label, "", false);
        }
        root.known = now;
    }

    function human(bytes: var): string {
        const b = Number(bytes) || 0;
        const units = ["B", "KB", "MB", "GB", "TB"];
        let i = 0, v = b;
        while (v >= 1000 && i < units.length - 1) {
            v /= 1000;
            i++;
        }
        return `${v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)} ${units[i]}`;
    }

    function shq(s: string): string {
        return "'" + `${s}`.replace(/'/g, "'\\''") + "'";
    }

    // Mount if nothing did, then open the mount point.
    function open(path: string): void {
        const p = root.shq(path);
        Quickshell.execDetached(["sh", "-c", `mp=$(lsblk -no MOUNTPOINT ${p} | head -n1); `
            + `[ -n "$mp" ] || mp=$(udisksctl mount -b ${p} --no-user-interaction 2>/dev/null | sed -n 's/.* at \\(.*\\)$/\\1/p' | sed 's/\\.$//'); `
            + `[ -n "$mp" ] && exec xdg-open "$mp"`]);
    }

    // Also IPC `island eventDemo drive|driveOff`.
    function announce(path: string, label: string, size: string, added: bool): void {
        root.events.cancel(`drive:${added ? "off" : "on"}:${path}`);
        root.events.post({
            key: `drive:${added ? "on" : "off"}:${path}`,
            glyph: "drive",
            glyphArgs: added ? {} : { eject: true },
            icon: "",
            color: added ? "qsBlue" : "islandFg",
            texts: added ? [label, size] : [label, I18n.tr("Removed")],
            tap: added ? () => root.open(path) : null
        });
    }
}
