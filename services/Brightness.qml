import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Backlight via brightnessctl. External changes (compositor binds running
// brightnessctl directly, other tools) are picked up by an inotify watch on
// the sysfs `brightness` file (noctalia approach): writes through the VFS
// raise IN_MODIFY even on sysfs (verified Oct 2026, gmux_backlight).
QtObject {
    id: root

    property real brightness: 0
    readonly property real step: Config.data.brightness.step
    property bool initialized: false
    // Device picked by brightnessctl (its default = first backlight).
    property string device: ""
    property string deviceClass: "backlight"
    property int maxRaw: 0
    // OsdWatcher skips changes until this timestamp (UI sliders call quiet()).
    property real osdQuietUntil: 0

    function quiet(): void {
        root.osdQuietUntil = Date.now() + Config.data.osd.quietMs;
    }

    function setBrightness(value: real): void {
        if (!initialized)
            return;
        value = Math.max(0, Math.min(1, value));
        const percent = Math.max(1, Math.round(value * 100));
        if (Math.round(brightness * 100) === percent)
            return;
        brightness = value;
        Quickshell.execDetached(["brightnessctl", "-q", "s", `${percent}%`]);
    }

    function increase(): void { setBrightness(brightness + step); }
    function decrease(): void { setBrightness(brightness - step); }

    // `brightnessctl -m`: device,class,current,percent,max
    property Process initProc: Process {
        running: true
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split("\n")[0].split(",");
                const c = parseInt(f[2]), m = parseInt(f[4]);
                if (f.length < 5 || isNaN(c) || isNaN(m) || m <= 0)
                    return;
                root.device = f[0];
                root.deviceClass = f[1];
                root.maxRaw = m;
                root.brightness = c / m;
                root.initialized = true;
            }
        }
    }

    property FileView sysfs: FileView {
        path: root.device !== "" ? `/sys/class/${root.deviceClass}/${root.device}/brightness` : ""
        watchChanges: true
        blockLoading: false
        onFileChanged: reload()
        onLoaded: {
            const c = parseInt(text().trim());
            if (isNaN(c) || root.maxRaw <= 0)
                return;
            const v = c / root.maxRaw;
            // Our own optimistic set already holds the rounded percent:
            // don't let the raw readback nudge it (spurious OSD repaint).
            if (Math.round(v * 100) !== Math.round(root.brightness * 100))
                root.brightness = v;
        }
    }
}
