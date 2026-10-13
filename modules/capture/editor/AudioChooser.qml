import QtQuick
import "../../../components"
import "../../../config"

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
        { v: "none", label: I18n.tr("No audio"), glyph: "" },
        { v: "system", label: I18n.tr("System"), glyph: "" },
        { v: "mic", label: I18n.tr("Microphone"), glyph: "" },
        { v: "both", label: I18n.tr("Both"), glyph: "" }
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

    // Birth like the toolbar: the bar starts under the chasing square and
    // springs out to its slot while fading in (first appearance only); it
    // retracts back into the bubble when the selection is dropped for a new one.
    property bool shown: false
    property bool retracting: false
    property bool born: false
    property bool springy: false
    property bool bornOnce: false
    property point origin: Qt.point(0, 0)
    visible: root.shown || root.retracting

    function bubbleOrigin(): point {
        const m = root.ed.capture.motion;
        return Qt.point(m.centerX - root.ed.ox - bar.width / 2, m.centerY - root.ed.oy - bar.height / 2);
    }

    onShownChanged: {
        if (root.shown) {
            if (root.bornOnce)
                return;
            retractEnd.stop();
            root.retracting = false;
            root.origin = root.bubbleOrigin();
            root.springy = false;
            root.born = false;
            root.springy = true;
            root.born = true;
            root.bornOnce = true;
        } else if (!root.ed.hasSelection && root.born) {
            root.origin = Qt.binding(() => root.bubbleOrigin());
            root.retracting = true;
            root.born = false;
            retractEnd.restart();
        }
    }

    Timer {
        id: retractEnd
        interval: root.cfg.squareHideDelayMs
        onTriggered: root.retracting = false
    }

    Connections {
        target: root.ed
        function onHasSelectionChanged(): void {
            if (!root.ed.hasSelection)
                root.bornOnce = false;
        }
    }

    Rectangle {
        id: bar
        x: root.born ? root.px : root.origin.x
        y: root.born ? root.py : root.origin.y
        opacity: root.born ? 1 : 0
        // Arc like the toolbar: the shorter axis springs harder.
        readonly property real adx: Math.abs(root.px - root.origin.x)
        readonly property real ady: Math.abs(root.py - root.origin.y)
        Behavior on x { enabled: root.springy; Spring { stiffness: root.cfg.birthSpring * (1 + root.cfg.birthArc * bar.ady / Math.max(1, bar.adx + bar.ady)); damp: root.cfg.birthDamping } }
        Behavior on y { enabled: root.springy; Spring { stiffness: root.cfg.birthSpring * (1 + root.cfg.birthArc * bar.adx / Math.max(1, bar.adx + bar.ady)); damp: root.cfg.birthDamping } }
        Behavior on opacity { enabled: root.springy; NumberAnimation { duration: root.born ? root.cfg.fadeInMs : root.cfg.squareHideDelayMs } }
        width: row.implicitWidth + root.cfg.toolSpacing * 2
        height: root.cfg.toolButtonSize + root.cfg.toolSpacing * 2
        // Concentric with the chips' tile radius.
        radius: root.cfg.toolRadius + root.cfg.toolSpacing
        color: root.theme.islandBg

        Row {
            id: row
            anchors.centerIn: parent
            spacing: root.cfg.toolSpacing

            Repeater {
                model: root.choices

                // Icon tile look (wallpaper settings), like the buttons.
                IconTile {
                    id: chip
                    required property var modelData
                    readonly property bool preselected: root.recorder.defaultAudio() === modelData.v
                    theme: root.theme
                    width: chipRow.implicitWidth + root.cfg.panelPad
                    height: root.cfg.toolButtonSize
                    radius: root.cfg.toolRadius
                    fill: preselected ? root.theme.accentRed : "transparent"
                    hovered: chipMa.containsMouse

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
                tile: true
                radius: root.cfg.toolRadius
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
