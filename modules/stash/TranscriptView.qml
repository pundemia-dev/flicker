import QtQuick
import Quickshell.Io
import "../../components"
import "../../config"
import "TranscriptText.js" as TT

// Stash `transcript` view: the WhisperX text of one tray file
// (services/Transcribe). Header (back · name · language/model), paragraphs
// without timecodes (wheel scroll — no Flickable; a click on a paragraph
// copies it, swipe-up over one still closes the module), footer "Copy all"
// · ".srt" · "Save" | re-run. Without a result yet: queue / progress /
// error state with a Transcribe / Retry button.
Item {
    id: root
    required property string path
    required property var stash
    required property var cfg
    required property var theme
    signal back
    signal closeRequested

    readonly property var tr: root.stash.transcribe
    readonly property var tcfg: Config.data.transcribe
    readonly property string fileName: root.path.split("/").pop()
    readonly property string stem: root.fileName.includes(".") ? root.fileName.slice(0, root.fileName.lastIndexOf(".")) : root.fileName
    // Re-read on every Transcribe change (stateOf is a function).
    readonly property string fileState: { root.tr.known; root.tr.queue; root.tr.current; root.tr.errors; return root.tr.stateOf(root.path); }
    readonly property bool ready: root.fileState === "done" && root.doc !== null
    property var doc: null
    readonly property var paras: root.doc ? TT.paragraphs(root.doc, root.tcfg.paragraphGapSec, root.tcfg.paragraphMaxChars) : []
    readonly property string speakerLabel: I18n.tr("Speaker %1")
    readonly property real gap: root.cfg.gap

    FileView {
        id: result
        path: root.fileState === "done" ? root.tr.resultFor(root.path) : ""
        watchChanges: true
        printErrors: false
        onFileChanged: result.reload()
        onLoaded: {
            try {
                root.doc = JSON.parse(result.text());
            } catch (e) {
                root.doc = null;
            }
        }
        onPathChanged: if (result.path === "") root.doc = null
    }

    // ── Feedback line in the footer ("Copied", "Saved: x.txt") ──
    property string note: ""
    function flash(text: string): void {
        root.note = text;
        noteTimer.restart();
    }
    Timer {
        id: noteTimer
        interval: root.cfg.copiedFlashMs * 2
        onTriggered: root.note = ""
    }

    function saveDir(): string {
        const d = root.tcfg.saveDir ?? "";
        return d === "" ? root.stash.stashDir : root.stash.expand(d);
    }
    function copyAll(): void {
        root.tr.copy(TT.plain(root.paras, root.speakerLabel));
        root.flash(I18n.tr("Copied"));
    }
    function saveAs(ext: string): void {
        const target = `${root.saveDir()}/${root.stem}.${ext}`;
        root.tr.save(target, ext === "srt" ? TT.srt(root.doc, root.speakerLabel) : TT.plain(root.paras, root.speakerLabel));
        root.flash(I18n.tr("Saved: %1").arg(target.split("/").pop()));
    }

    // ── Header ──
    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.cfg.pickerHeaderHeight

        IconButton {
            id: backBtn
            theme: root.theme
            anchors.verticalCenter: parent.verticalCenter
            width: header.height
            height: header.height
            glyph: ""
            onClicked: root.back()
        }
        Text {
            anchors.left: backBtn.right
            anchors.leftMargin: root.gap
            anchors.right: meta.left
            anchors.rightMargin: root.gap
            anchors.verticalCenter: parent.verticalCenter
            text: root.fileName
            color: root.theme.islandFg
            font.pixelSize: root.theme.fontSizeClock
            font.weight: Font.DemiBold
            elide: Text.ElideMiddle
        }
        Text {
            id: meta
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.ready ? [root.doc.language, root.doc.model].filter(s => !!s).join(" · ") : ""
            color: root.theme.subtleFg
            font.pixelSize: root.theme.fontSizeTiny
        }
    }

    // ── Body ──
    Item {
        id: viewport
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: root.gap
        anchors.bottom: footer.top
        anchors.bottomMargin: root.gap
        clip: true

        readonly property real maxScroll: Math.max(0, body.height - viewport.height)
        property real scroll: 0
        onMaxScrollChanged: viewport.scroll = Math.min(viewport.scroll, viewport.maxScroll)

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 2;
                viewport.scroll = Math.max(0, Math.min(viewport.maxScroll, viewport.scroll - delta));
            }
        }

        Column {
            id: body
            width: viewport.width
            y: -scrollY
            spacing: 2
            visible: root.ready
            property real scrollY: viewport.scroll
            Behavior on scrollY { Spring { stiffness: 6; damp: 0.6 } }

            Repeater {
                model: root.paras

                Paragraph {}
            }
        }

        // No result (yet): queued / running / failed / never asked.
        Column {
            anchors.centerIn: parent
            width: Math.min(parent.width, 320)
            spacing: root.gap
            visible: !root.ready

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.fileState === "running"
                    ? (root.tr.stage === "loading" ? I18n.tr("Loading model…")
                        : root.tr.stage === "aligning" ? I18n.tr("Aligning words…")
                        : root.tr.stage === "diarizing" ? I18n.tr("Finding speakers…")
                        : I18n.tr("Transcribing…"))
                    : root.fileState === "queued" ? I18n.tr("Queued · %1 ahead").arg(root.tr.queue.indexOf(root.path) + (root.tr.busy ? 1 : 0))
                    : root.fileState === "error" ? I18n.tr("Transcription failed")
                    : root.fileState === "done" ? I18n.tr("Loading…")
                    : I18n.tr("Not transcribed yet")
                color: root.theme.islandFg
                font.pixelSize: root.theme.fontSizeClock
            }
            ProgressBar {
                width: parent.width
                visible: root.fileState === "running"
                value: root.tr.progress
                trackColor: root.theme.cardTrack
                fillColor: root.theme.cardBlue
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
                visible: text !== ""
                text: root.fileState === "running" && root.tr.stage !== "loading" ? `${Math.round(root.tr.progress * 100)}%`
                    : root.fileState === "error" ? (root.tr.errors[root.path] ?? "") : ""
                color: root.theme.subtleFg
                font.pixelSize: root.theme.fontSizeBody
            }
            PillButton {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.fileState === "" || root.fileState === "error"
                label: root.fileState === "error" ? I18n.tr("Retry") : I18n.tr("Transcribe")
                accent: true
                onClicked: root.tr.request(root.path)
            }
            PillButton {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.fileState === "running" || root.fileState === "queued"
                label: I18n.tr("Cancel")
                onClicked: root.tr.cancel(root.path)
            }
        }
    }

    // ── Footer ──
    Item {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.cfg.actionsHeight

        Row {
            spacing: root.gap
            height: parent.height
            PillButton {
                label: I18n.tr("Copy all")
                disabled: !root.ready
                onClicked: root.copyAll()
            }
            PillButton {
                label: ".srt"
                disabled: !root.ready
                onClicked: root.saveAs("srt")
            }
            PillButton {
                label: I18n.tr("Save")
                disabled: !root.ready
                onClicked: root.saveAs("txt")
            }
        }
        Text {
            anchors.right: rerunBtn.left
            anchors.rightMargin: root.gap
            anchors.verticalCenter: parent.verticalCenter
            text: root.note
            color: root.theme.subtleFg
            font.pixelSize: root.theme.fontSizeBody
            opacity: root.note !== "" ? 1 : 0
            Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
        }
        // Transcribe again with the current settings (model / language).
        IconButton {
            id: rerunBtn
            anchors.right: parent.right
            theme: root.theme
            width: footer.height
            height: footer.height
            disabled: root.fileState !== "done"
            glyph: ""
            onClicked: root.tr.rerun(root.path)
        }
    }

    // One paragraph: optional speaker line, text; hover plate, click =
    // copy (plate flashes the accent), swipe-up = close the module (the
    // paragraph grabs the press, so GestureZones never sees it).
    component Paragraph: Item {
        id: para
        required property var modelData
        required property int index
        readonly property bool newSpeaker: para.modelData.speaker !== ""
            && (para.index === 0 || root.paras[para.index - 1].speaker !== para.modelData.speaker)
        property bool flashed: false

        width: body.width
        height: col.height + 8

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: para.flashed ? Qt.alpha(root.theme.cardBlue, 0.35) : root.theme.cardBg
            opacity: para.flashed || ma.containsMouse ? 1 : 0
            Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
        }
        Column {
            id: col
            x: 6
            y: 4
            width: para.width - 12
            spacing: 2
            Text {
                visible: para.newSpeaker
                text: TT.speakerName(para.modelData.speaker, root.speakerLabel)
                color: root.theme.subtleFg
                font.pixelSize: root.theme.fontSizeTiny
                font.weight: Font.DemiBold
            }
            Text {
                width: col.width
                text: para.modelData.text
                wrapMode: Text.Wrap
                color: root.theme.islandFg
                font.pixelSize: root.cfg.transcriptFontSize
                lineHeight: 1.15
            }
        }
        Timer {
            id: flashTimer
            interval: root.cfg.copiedFlashMs
            onTriggered: para.flashed = false
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            property real pressY: 0
            property bool swiped: false
            onPressed: mouse => {
                ma.pressY = mouse.y;
                ma.swiped = false;
            }
            onPositionChanged: mouse => {
                if (ma.pressed && !ma.swiped && ma.pressY - mouse.y > 30) {
                    ma.swiped = true;
                    root.closeRequested();
                }
            }
            onClicked: {
                if (ma.swiped)
                    return;
                root.tr.copy(para.modelData.text + "\n");
                para.flashed = true;
                flashTimer.restart();
                root.flash(I18n.tr("Copied"));
            }
        }
    }

    component PillButton: Rectangle {
        id: pb
        property string label
        property bool accent: false
        property bool disabled: false
        signal clicked
        height: root.cfg.actionsHeight
        width: pbText.implicitWidth + height
        radius: height / 2
        color: pb.accent ? root.theme.cardBlue : (pbMa.containsMouse && !pb.disabled ? root.theme.cardTrack : root.theme.cardBg)
        opacity: pb.disabled ? 0.4 : 1
        scale: pbMa.pressed && !pb.disabled ? 0.94 : 1
        Behavior on scale { Spring { stiffness: 6; damp: 0.4; eps: 0.002 } }
        Text {
            id: pbText
            anchors.centerIn: parent
            text: pb.label
            color: root.theme.islandFg
            font.pixelSize: root.theme.fontSizeBody
        }
        MouseArea {
            id: pbMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (!pb.disabled) pb.clicked()
        }
    }
}
