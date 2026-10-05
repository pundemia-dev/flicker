import QtQuick
import "../config"

// VolumeIcon's pulse() for plain glyphs: `value` grows to `peak` and settles
// back to 1 (timed, same Config.volumeIcon bump curve). Multiply it into the
// glyph's scale and call bump() — e.g. brightness reaching 100%.
Item {
    id: root
    readonly property var cfg: Config.data.volumeIcon
    property real peak: root.cfg.pulseScale
    property real value: 1

    function bump(): void {
        anim.restart();
    }

    SequentialAnimation {
        id: anim
        NumberAnimation {
            target: root
            property: "value"
            to: root.peak
            duration: root.cfg.bumpUpMs
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "value"
            to: 1
            duration: root.cfg.bumpDownMs
            easing.type: Easing.InOutCubic
        }
    }
}
