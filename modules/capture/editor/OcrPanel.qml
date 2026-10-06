import QtQuick
import Quickshell.Io
import "../../../components"
import "../../../config"

// Inline OCR (port of pShell OcrPanel + RegionEditor OCR state): the
// selection stays adjustable while the text is shown — moving/resizing the
// frame re-crops on release, a language chip re-runs on the kept crop. The
// crop is the PURE grab (annotations never pollute recognition); results
// are copied silently. Placed in the roomiest side strip around the
// selection, clear of the toolbar ring; glides (spring) when it relocates.
Item {
    id: root
    required property var editor
    required property real clearance

    readonly property var ed: root.editor
    readonly property var theme: root.editor.theme
    readonly property var cfg: root.editor.cfg
    readonly property var actions: root.editor.actions

    property bool open: false
    property bool running: false
    property string text: ""
    property string langs: ""
    readonly property string cropPath: root.actions.scratchPng("ocr", root.ed.screenName)

    function initialLangs(): string {
        const def = root.cfg.ocrDefaultLang;
        if (def === "auto")
            return root.actions.lastOcrLangs;
        return def === "all" ? "" : def;
    }

    function toggle(): void {
        if (root.open) {
            root.open = false;
            return;
        }
        if (!root.ed.hasSelection)
            return;
        root.langs = root.initialLangs();
        root.open = true;
        root.recrop();
    }

    function selectLangs(l: string): void {
        if (root.langs === l)
            return;
        root.langs = l;
        root.actions.lastOcrLangs = l;
        root.recognize();
    }

    function recrop(): void {
        if (!root.open || !root.ed.hasSelection)
            return;
        root.running = true;
        ocrProc.running = false;
        cropProc.running = false;
        cropProc.command = root.actions.cropCommand(root.ed.srcPath, root.ed.physRect(), root.cropPath);
        cropProc.running = true;
    }

    function recognize(): void {
        root.running = true;
        ocrProc.running = false;
        const l = root.langs !== "" ? root.langs : (root.actions.ocrLangsAvailable.join("+") || "eng");
        ocrProc.command = ["tesseract", root.cropPath, "stdout", "-l", l];
        ocrProc.running = true;
    }

    Process {
        id: cropProc
        onExited: code => code === 0 ? root.recognize() : (root.running = false)
    }

    Process {
        id: ocrProc
        stdout: StdioCollector {
            id: ocrOut
            onStreamFinished: {
                root.text = ocrOut.text.trim();
                root.running = false;
                if (root.text)
                    root.actions.copyText(root.text, "");
            }
        }
    }

    readonly property real panelW: root.cfg.ocrPanelWidth
    readonly property real panelH: col.implicitHeight + root.cfg.panelPad * 2
    readonly property point place: {
        const m = root.cfg.toolSpacing, c = root.clearance + m, e = root.ed;
        const side = [
            { s: "bottom", v: root.height - (e.selY + e.selH) },
            { s: "top", v: e.selY },
            { s: "right", v: root.width - (e.selX + e.selW) },
            { s: "left", v: e.selX }
        ].sort((a, b) => b.v - a.v)[0].s;
        let x = e.selX + e.selW / 2 - root.panelW / 2;
        let y = e.selY + e.selH / 2 - root.panelH / 2;
        if (side === "bottom") y = e.selY + e.selH + c;
        else if (side === "top") y = e.selY - c - root.panelH;
        else if (side === "right") x = e.selX + e.selW + c;
        else x = e.selX - c - root.panelW;
        return Qt.point(Math.max(m, Math.min(root.width - root.panelW - m, x)), Math.max(m, Math.min(root.height - root.panelH - m, y)));
    }

    visible: opacity > 0.01
    opacity: root.open ? (root.ed.interacting ? 0.4 : 1) : 0
    Behavior on opacity { NumberAnimation { duration: root.cfg.fadeInMs } }

    Rectangle {
        x: root.place.x
        y: root.place.y
        width: root.panelW
        height: root.panelH
        radius: root.cfg.panelRadius
        color: root.theme.islandBg
        // Glide only on relocation while open (frame moved/resized); the
        // opening position is taken as is.
        Behavior on x { enabled: root.open; Spring {} }
        Behavior on y { enabled: root.open; Spring {} }

        // Swallow clicks: no selection drag through the panel.
        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: col
            anchors.centerIn: parent
            width: root.panelW - root.cfg.panelPad * 2
            spacing: root.cfg.toolSpacing * 1.5

            Item {
                width: parent.width
                height: root.cfg.toolButtonSize

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: I18n.tr("Text Recognition")
                        color: root.theme.islandFg
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.fontSizeClock
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: root.running ? I18n.tr("Recognizing…") : (root.text !== "" ? I18n.tr("Copied to clipboard") : I18n.tr("No text found"))
                        color: root.theme.subtleFg
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.fontSizeTiny
                    }
                }

                Row {
                    anchors.right: parent.right
                    spacing: root.cfg.toolSpacing
                    IconButton {
                        theme: root.theme
                        width: root.cfg.toolButtonSize
                        height: width
                        glyph: ""
                        iconSize: root.cfg.toolIconSize
                        disabled: root.running || root.text === ""
                        onClicked: root.actions.copyText(root.text, I18n.tr("Text copied"))
                    }
                    IconButton {
                        theme: root.theme
                        width: root.cfg.toolButtonSize
                        height: width
                        glyph: ""
                        iconSize: root.cfg.toolIconSize
                        onClicked: root.open = false
                    }
                }
            }

            Flow {
                width: parent.width
                spacing: root.cfg.toolSpacing

                Repeater {
                    model: [""].concat(root.actions.ocrLangsAvailable)

                    Rectangle {
                        id: chip
                        required property string modelData
                        readonly property bool current: root.langs === modelData
                        width: chipText.implicitWidth + root.cfg.panelPad
                        height: chipText.implicitHeight + root.cfg.toolSpacing
                        radius: height / 2
                        color: current ? root.theme.cardBlue : root.theme.cardBg
                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: chip.modelData === "" ? I18n.tr("All") : chip.modelData
                            color: root.theme.islandFg
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fontSizeIndicator
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectLangs(chip.modelData)
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: Math.min(root.height * 0.4, flick.contentHeight + root.cfg.panelPad)
                radius: root.cfg.toolRadius
                color: root.theme.cardBg

                Flickable {
                    id: flick
                    anchors.fill: parent
                    anchors.margins: root.cfg.panelPad / 2
                    clip: true
                    contentWidth: width
                    contentHeight: ocrEdit.height
                    boundsBehavior: Flickable.StopAtBounds

                    TextEdit {
                        id: ocrEdit
                        width: flick.width
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        text: root.text !== "" ? root.text : (root.running ? "…" : I18n.tr("(empty)"))
                        color: root.text !== "" ? root.theme.islandFg : root.theme.subtleFg
                        selectionColor: root.theme.cardBlue
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.fontSizeBody
                    }
                }
            }
        }
    }
}
