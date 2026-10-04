import QtQuick
import "../../components"

// Recording controls in the island (red clock plate click; port of pShell
// RecordPill's recording row): pulsing dot + elapsed time, then discard /
// audio source (cycles none → system → mic → both, switched live) / pause
// / stop. Stop and discard close the module (the plate leaves with it).
Item {
    id: root
    required property var recorder
    required property var theme
    required property var cfg
    signal closeRequested

    // Stopped elsewhere (IPC / plate): nothing left to control.
    Connections {
        target: root.recorder
        function onRecordingChanged(): void {
            if (!root.recorder.recording)
                root.closeRequested();
        }
    }

    readonly property var audioGlyphs: ({ none: "", system: "", mic: "", both: "" })

    Row {
        anchors.centerIn: parent
        spacing: root.cfg.toolSpacing * 2

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: root.cfg.toolSpacing * 2
            height: width
            radius: width / 2
            color: root.recorder.paused ? root.theme.subtleFg : root.theme.accentRed

            SequentialAnimation on opacity {
                running: root.recorder.recording && !root.recorder.paused
                loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: root.cfg.fadeInMs * 3 }
                NumberAnimation { to: 1; duration: root.cfg.fadeInMs * 3 }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.recorder.elapsedText
            color: root.theme.islandFg
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fontSizeClock + 4
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }

        Repeater {
            model: [
                { glyph: "", fg: root.theme.accentRed, run: () => { root.recorder.discard(); root.closeRequested(); } },
                { glyph: root.audioGlyphs[root.recorder.audio] ?? "", fg: root.theme.islandFg, run: () => root.recorder.cycleAudio() },
                { glyph: root.recorder.paused ? "" : "", fg: root.theme.islandFg, run: () => root.recorder.togglePause() },
                { glyph: "", fg: root.theme.islandFg, bg: root.theme.accentRed, run: () => { root.recorder.stop(); root.closeRequested(); } }
            ]

            IconButton {
                required property var modelData
                anchors.verticalCenter: parent.verticalCenter
                theme: root.theme
                width: root.cfg.toolButtonSize + root.cfg.toolSpacing
                height: width
                glyph: modelData.glyph
                fg: modelData.fg
                bg: modelData.bg ?? root.theme.cardBg
                iconSize: root.cfg.toolIconSize
                onClicked: modelData.run()
            }
        }
    }
}
