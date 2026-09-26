import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

QtObject {
    id: root

    property real brightness: 0
    readonly property real step: Config.data.brightness.step
    property bool initialized: false

    function setBrightness(value: real): void {
        if (!initialized)
            return;
        value = Math.max(0, Math.min(1, value));
        const percent = Math.max(1, Math.round(value * 100));
        if (Math.round(brightness * 100) === percent)
            return;
        brightness = value;
        Quickshell.execDetached(["brightnessctl", "s", `${percent}%`]);
    }

    function increase(): void { setBrightness(brightness + step); }
    function decrease(): void { setBrightness(brightness - step); }

    property Process initProc: Process {
        running: true
        command: ["sh", "-c", "echo $(brightnessctl g) $(brightnessctl m)"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [cur, max] = text.trim().split(" ");
                const c = parseInt(cur), m = parseInt(max);
                if (!isNaN(c) && !isNaN(m) && m > 0) {
                    root.brightness = c / m;
                    root.initialized = true;
                }
            }
        }
    }
}
