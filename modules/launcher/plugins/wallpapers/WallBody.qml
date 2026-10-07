import QtQuick
import "../../../../components"

// The plugin's body: the carousel, or the settings panel over the same
// area (Ctrl+I) — swapped with the blur-fade (FadeBlur), the island keeps
// its size.
Item {
    id: root
    required property var plugin
    required property var service
    required property var theme
    required property var c
    required property var lc

    FadeBlur {
        anchors.fill: parent
        shown: !root.plugin.settingsOpen

        WallCarousel {
            anchors.fill: parent
            plugin: root.plugin
            service: root.service
            theme: root.theme
            c: root.c
            lc: root.lc
        }
    }

    FadeBlur {
        anchors.fill: parent
        shown: root.plugin.settingsOpen

        Loader {
            anchors.fill: parent
            active: parent.p > 0.01
            sourceComponent: WallSettings {
                plugin: root.plugin
                theme: root.theme
                c: root.c
                lc: root.lc
            }
        }
    }
}
