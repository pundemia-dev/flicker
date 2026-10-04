import QtQuick
import "../../../components"

// Record pending state (port of pShell RecordPill's chooser): audio chips
// next to the selection; recording starts only when one is clicked
// (Enter = the preselected one). Preselected = Recorder default ("auto" =
// last choice).
Item {
    id: root
    required property var editor

    readonly property var ed: root.editor
    readonly property var theme: root.editor.theme
    readonly property var cfg: root.editor.cfg
    readonly property var recorder: root.editor.capture.recorder
    readonly property var choices: [
        { v: "none", label: "Без звука", glyph: "" },
        { v: "system", label: "Система", glyph: "" },
        { v: "mic", label: "Микрофон", glyph: "" },
        { v: "both", label: "Оба", glyph: "" }
    ]

    // Below the selection, else above, else inside at the bottom.
    readonly property real px: Math.max(0, Math.min(root.width - bar.width, root.ed.selX + root.ed.selW / 2 - bar.width / 2))
    readonly property real py: {
        const e = root.ed, s = root.cfg.toolSpacing;
        if (e.selY + e.selH + s + bar.height <= root.height)
            return e.selY + e.selH + s;
        if (e.selY - s - bar.height >= 0)
            return e.selY - s - bar.height;
        return e.selY + e.selH - s - bar.height;
    }

    opacity: visible ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: root.cfg.fadeInMs } }

    Rectangle {
        id: bar
        x: root.px
        y: root.py
        width: row.implicitWidth + root.cfg.toolSpacing * 2
        height: root.cfg.toolButtonSize + root.cfg.toolSpacing * 2
        radius: height / 2
        color: root.theme.islandBg

        Row {
            id: row
            anchors.centerIn: parent
            spacing: root.cfg.toolSpacing

            Repeater {
                model: root.choices

                Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool preselected: root.recorder.defaultAudio() === modelData.v
                    width: chipRow.implicitWidth + root.cfg.panelPad
                    height: root.cfg.toolButtonSize
                    radius: height / 2
                    color: preselected ? root.theme.accentRed : (chipMa.containsMouse ? root.theme.cardTrack : root.theme.cardBg)

                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: root.cfg.toolSpacing
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData.glyph
                            color: root.theme.islandFg
                            font.family: root.theme.iconFamily
                            font.pixelSize: root.cfg.toolIconSize
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData.label
                            color: root.theme.islandFg
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fontSizeBody
                        }
                    }

                    MouseArea {
                        id: chipMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.ed.startRecording(chip.modelData.v)
                    }
                }
            }

            IconButton {
                theme: root.theme
                width: root.cfg.toolButtonSize
                height: width
                glyph: ""
                iconSize: root.cfg.toolIconSize
                onClicked: {
                    if (root.ed.capture.mode === "record")
                        root.ed.capture.cancel();
                    else
                        root.ed.pendingRecord = false;
                }
            }
        }
    }
}
