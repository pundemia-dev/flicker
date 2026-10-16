import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../../components"
import "../../config"

// Quick Look body for files without a picture: the head of a text file
// (`previewTextBytes`), a folder's listing, an archive's table of contents
// (bsdtar -tf), or for anything else the file icon + `file -b` description
// + size. Text scrolls on the wheel (no Flickable: presses stay free for
// the swipe-up close).
Item {
    id: root
    required property string path
    required property string kind
    required property var stash
    required property var cfg
    required property var theme

    property string body: ""
    property bool loaded: false
    readonly property bool info: root.kind === "other"
    readonly property string q: root.stash.shq(root.path)

    Process {
        running: true
        command: ["bash", "-c",
            root.kind === "text" ? `head -c ${root.cfg.previewTextBytes} -- ${root.q}`
            : root.kind === "dir" ? `cd -- ${root.q} && ls -1Ap | head -n 500`
            : root.kind === "archive" ? `{ bsdtar -tf ${root.q} 2>/dev/null || 7z l -ba -- ${root.q} 2>/dev/null; } | head -n 500`
            : `file -b -- ${root.q}; du -sh -- ${root.q} | cut -f1`]
        stdout: StdioCollector {
            id: out
            onStreamFinished: {
                root.body = out.text;
                root.loaded = true;
            }
        }
    }

    // ── Listing / text ──
    Item {
        id: viewport
        anchors.fill: parent
        visible: !root.info
        clip: true

        readonly property real maxScroll: Math.max(0, content.height - viewport.height)
        property real scroll: 0

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 2;
                viewport.scroll = Math.max(0, Math.min(viewport.maxScroll, viewport.scroll - delta));
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: 10
            color: root.theme.cardBg
        }
        Text {
            id: content
            x: 12
            y: 10 - scrollY
            width: viewport.width - 24
            property real scrollY: viewport.scroll
            Behavior on scrollY { Spring { stiffness: 6; damp: 0.6 } }
            text: root.loaded ? (root.body !== "" ? root.body : I18n.tr("Empty")) : I18n.tr("Loading…")
            textFormat: Text.PlainText
            wrapMode: root.kind === "text" ? Text.WrapAnywhere : Text.NoWrap
            elide: root.kind === "text" ? Text.ElideNone : Text.ElideMiddle
            color: root.body !== "" ? root.theme.islandFg : root.theme.subtleFg
            font.family: "monospace"
            font.pixelSize: root.cfg.previewTextSize
            lineHeight: 1.1
        }
    }

    // ── Other files: icon + description ──
    Row {
        visible: root.info
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        spacing: root.cfg.gap * 2

        IconImage {
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: 56
            source: Quickshell.iconPath("application-x-generic")
            asynchronous: true
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 56 - parent.spacing
            spacing: 4
            Repeater {
                model: root.body.trim().split("\n")
                Text {
                    required property string modelData
                    required property int index
                    width: parent.width
                    text: modelData
                    color: index === 0 ? root.theme.islandFg : root.theme.subtleFg
                    font.pixelSize: index === 0 ? root.theme.fontSizeClock : root.theme.fontSizeBody
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }
        }
    }
}
