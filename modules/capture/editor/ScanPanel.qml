import QtQuick
import Quickshell
import Quickshell.Io
import "../../../components"
import "../../../config"

// QR / barcode scan (sibling of OcrPanel): zbarimg on the PURE grab crop of
// the selection (inverted = dark-mode codes too), re-run when the frame is
// released after a move/resize. Every found code gets an outline on the
// screen and a row in the panel (click = copy, links get "open"); a single
// result is copied silently. Placed like the OCR panel (roomiest side).
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
    // [{ type, data, box (editor coords) }]
    property var results: []
    property int hovered: -1
    readonly property string cropPath: root.actions.scratchPng("scan", root.ed.screenName)

    function toggle(): void {
        if (root.open) {
            root.open = false;
            return;
        }
        if (!root.ed.hasSelection)
            return;
        root.ed.ocrPanel.open = false;
        root.open = true;
        root.recrop();
    }

    function recrop(): void {
        if (!root.open || !root.ed.hasSelection)
            return;
        root.running = true;
        root.results = [];
        scanProc.running = false;
        cropProc.running = false;
        cropProc.origin = root.ed.physRect();
        cropProc.command = root.actions.cropCommand(root.ed.srcPath, cropProc.origin, root.cropPath);
        cropProc.running = true;
    }

    function isLink(s: string): bool {
        return /^(https?:\/\/|mailto:)\S+$/i.test(s.trim());
    }

    function allText(): string {
        return root.results.map(r => r.data).join("\n");
    }

    function copyRow(i: int): void {
        root.actions.copyText(root.results[i].data, I18n.tr("Code copied"));
    }

    // zbarimg --xml: one <symbol> per code; data in CDATA (base64 for binary).
    function parse(xml: string, o: var): var {
        const out = [];
        const re = /<symbol type='([^']*)'[^>]*>([\s\S]*?)<data( format='base64')?><!\[CDATA\[([\s\S]*?)\]\]><\/data>/g;
        let m;
        while ((m = re.exec(xml)) !== null) {
            const pts = (/points='([^']*)'/.exec(m[2])?.[1] ?? "").trim().split(/\s+/).filter(p => p).map(p => p.split(",").map(Number));
            const xs = pts.map(p => p[0]), ys = pts.map(p => p[1]);
            const d = root.ed.dpr, pad = root.cfg.scanBoxPad;
            const box = pts.length ? Qt.rect((o.x + Math.min(...xs)) / d - pad, (o.y + Math.min(...ys)) / d - pad,
                (Math.max(...xs) - Math.min(...xs)) / d + pad * 2, (Math.max(...ys) - Math.min(...ys)) / d + pad * 2) : null;
            out.push({ type: m[1].replace("-Code", "").replace("_", " "), data: m[3] ? Qt.atob(m[4]) : m[4], box: box });
        }
        return out;
    }

    Process {
        id: cropProc
        property var origin: null
        onExited: code => {
            if (code !== 0) {
                root.running = false;
                return;
            }
            scanProc.origin = cropProc.origin;
            scanProc.running = true;
        }
    }

    Process {
        id: scanProc
        property var origin: null
        command: ["zbarimg", "-q", "--xml", "-Stest-inverted", root.cropPath]
        stdout: StdioCollector {
            id: scanOut
            onStreamFinished: {
                root.results = root.parse(scanOut.text, scanProc.origin);
                root.running = false;
                if (root.results.length === 1)
                    root.actions.copyText(root.results[0].data, "");
            }
        }
    }

    // Outlines over the found codes (hidden while the frame is dragged).
    Repeater {
        model: root.open && !root.ed.interacting ? root.results.filter(r => r.box) : []

        Rectangle {
            required property var modelData
            required property int index
            x: modelData.box.x
            y: modelData.box.y
            width: modelData.box.width
            height: modelData.box.height
            radius: root.cfg.toolRadius / 2
            color: "transparent"
            border.color: root.theme.cardBlue
            border.width: root.hovered === index ? root.cfg.scanBoxWidth * 2 : root.cfg.scanBoxWidth
        }
    }

    readonly property real panelW: root.cfg.scanPanelWidth
    readonly property real panelH: col.implicitHeight + root.cfg.panelPad * 2
    readonly property point place: root.ed.panelPlace(root.panelW, root.panelH, root.clearance)

    visible: opacity > 0.01
    opacity: root.open ? (root.ed.interacting ? 0.4 : 1) : 0
    Behavior on opacity { NumberAnimation { duration: root.cfg.fadeInMs } }

    Rectangle {
        id: panelBox
        x: root.place.x
        y: root.place.y
        width: root.panelW
        height: root.panelH
        radius: root.cfg.panelRadius
        color: root.theme.islandBg
        transform: VelocityDeform {
            item: panelBox
        }
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
                        text: I18n.tr("Code Scan")
                        color: root.theme.islandFg
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.fontSizeClock
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: root.running ? I18n.tr("Scanning…")
                            : (root.results.length === 0 ? I18n.tr("No codes found")
                            : (root.results.length === 1 ? I18n.tr("Copied to clipboard")
                            : I18n.trN(root.results.length, "%1 code found", "%1 codes found").arg(root.results.length)))
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
                        tile: true
                        radius: root.cfg.toolRadius
                        width: root.cfg.toolButtonSize
                        height: width
                        glyph: ""
                        iconSize: root.cfg.toolIconSize
                        disabled: root.running || root.results.length === 0
                        onClicked: root.actions.copyText(root.allText(), I18n.tr("Code copied"))
                    }
                    IconButton {
                        theme: root.theme
                        tile: true
                        radius: root.cfg.toolRadius
                        width: root.cfg.toolButtonSize
                        height: width
                        glyph: ""
                        iconSize: root.cfg.toolIconSize
                        onClicked: root.open = false
                    }
                }
            }

            Repeater {
                model: root.results

                ScanRow {
                    required property var modelData
                    required property int index
                    width: col.width
                    panel: root
                    entry: modelData
                    onHoveredChanged: root.hovered = hovered ? index : (root.hovered === index ? -1 : root.hovered)
                    onCopy: root.copyRow(index)
                    onOpenLink: {
                        Quickshell.execDetached(["xdg-open", modelData.data.trim()]);
                        root.ed.capture.done();
                    }
                }
            }
        }
    }
}
