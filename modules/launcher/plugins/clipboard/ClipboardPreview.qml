import QtQuick
import Quickshell.Io
import "../../../../components"

// Side-panel preview of the selected entry (pShell ClipboardPreviewPanel
// port): image fitted, colour as a big swatch + HEX/RGB/HSL, text / url /
// path as the full decoded body (`cliphist list` only has a one-line
// preview; the decode is cached on the record). `svc` (not `service`) so
// the call site's `svc: service` is no self-reference.
Item {
    id: root
    required property var rec
    required property var svc
    required property var theme
    required property var cfg

    readonly property string type: root.rec?.type ?? ""
    readonly property bool isText: type === "text" || type === "url" || type === "path"
    property string fullText: root.rec?.value ?? ""

    onRecChanged: loadFull()
    Component.onCompleted: loadFull()

    function loadFull(): void {
        const r = root.rec;
        if (!r || !root.isText) {
            root.fullText = r?.value ?? "";
            return;
        }
        if (r.full !== undefined) {
            root.fullText = r.full;
            return;
        }
        root.fullText = r.value ?? "";
        decodeProc.rec = r;
        decodeProc.command = ["bash", "-c", `printf %s ${root.svc.shq(r.raw)} | ${root.svc.binary} decode`];
        decodeProc.running = true;
    }

    Process {
        id: decodeProc
        property var rec: null
        stdout: StdioCollector {
            onStreamFinished: {
                if (decodeProc.rec)
                    decodeProc.rec.full = this.text ?? "";
                if (decodeProc.rec === root.rec)
                    root.fullText = this.text ?? "";
            }
        }
    }

    // Image, fitted by aspect.
    Item {
        id: imageBox
        visible: root.type === "image"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: hint.top
        anchors.bottomMargin: 8
        readonly property real aspect: (root.rec?.width ?? 0) > 0 && (root.rec?.height ?? 0) > 0 ? root.rec.width / root.rec.height : 4 / 3
        readonly property bool wide: aspect >= width / Math.max(1, height)

        RoundedImage {
            anchors.centerIn: parent
            width: imageBox.wide ? parent.width : parent.height * imageBox.aspect
            height: imageBox.wide ? parent.width / imageBox.aspect : parent.height
            radius: root.cfg.itemRadius - root.cfg.itemPadding / 2
            source: imageBox.visible && root.rec ? "file://" + root.rec.imagePath : ""
            fallbackColor: root.theme.cardTrack
        }
    }

    // Colour swatch + conversions.
    Column {
        visible: root.type === "color"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Rectangle {
            width: parent.width
            height: width * 0.5
            radius: root.cfg.itemRadius - root.cfg.itemPadding / 2
            color: root.rec?.hex ?? "transparent"
            border.width: 1
            border.color: "#33FFFFFF"
        }
        Repeater {
            model: {
                if (root.type !== "color")
                    return [];
                const c = Qt.color(root.rec.hex);
                const r = Math.round(c.r * 255), g = Math.round(c.g * 255), b = Math.round(c.b * 255);
                return [
                    { k: "HEX", v: `#${[r, g, b].map(x => x.toString(16).padStart(2, "0")).join("").toUpperCase()}` },
                    { k: "RGB", v: `rgb(${r}, ${g}, ${b})` },
                    { k: "HSL", v: `hsl(${Math.round(Math.max(0, c.hslHue) * 360)}, ${Math.round(c.hslSaturation * 100)}%, ${Math.round(c.hslLightness * 100)}%)` }
                ];
            }
            Row {
                required property var modelData
                spacing: 10
                Text {
                    width: 36
                    text: modelData.k
                    font.weight: Font.DemiBold
                    font.pixelSize: root.cfg.subFontSize
                    color: root.theme.cardDim
                }
                Text {
                    text: modelData.v
                    font.family: "monospace"
                    font.pixelSize: root.cfg.subFontSize
                    color: root.theme.islandFg
                }
            }
        }
    }

    // Text / url / path body.
    Text {
        visible: root.isText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: hint.top
        anchors.bottomMargin: 8
        verticalAlignment: Text.AlignTop
        wrapMode: Text.Wrap
        elide: Text.ElideRight
        text: root.fullText
        font.family: root.type === "text" ? root.theme.fontFamily : "monospace"
        font.pixelSize: root.cfg.subFontSize
        color: root.theme.islandFg
    }

    Text {
        id: hint
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: "Enter — копировать" + (root.svc?.autoPaste ? " и вставить" : "") + " · Alt+Enter — только копировать"
        font.pixelSize: root.cfg.subFontSize - 1
        color: root.theme.cardDim
    }
}
