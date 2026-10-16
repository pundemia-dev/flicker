import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../../components"
import "../../config"
import "StashTypes.js" as Types

// Quick Look of one tray file (stash view "preview"): header (back · name ·
// n / m · open) over a body by kind — image / GIF fitted, PDF first page
// (pdftoppm), video + audio played (StashPreviewMedia), text file head,
// folder / archive listing, else icon + `file` description + size. The
// island is fitted through Stash.preview {kind, w, h} (StashMetrics).
// Keys (handleKey): Space / Esc back, ← / → previous / next file, Enter
// opens it in its app, P pauses media.
Item {
    id: root
    required property string path
    required property var stash
    required property var cfg
    required property var theme
    signal back
    signal step(int delta)

    readonly property var files: { root.stash.count; return root.stash.allPaths(); }
    readonly property int index: root.files.indexOf(root.path)
    readonly property string fileName: root.path.split("/").pop()
    readonly property bool isDir: { root.stash.count; return root.stash.isDirPath(root.path); }
    readonly property string kind: Types.kindOf(root.fileName, root.isDir)

    // Island fit: the body's natural size (image / page / video frame; 0
    // = not known yet or not visual). A Binding, not a write on load: a
    // cached image is ready before this item's onCompleted.
    Binding {
        target: root.stash
        property: "preview"
        value: ({ kind: root.kind, w: body.item?.naturalW ?? 0, h: body.item?.naturalH ?? 0 })
    }

    function openExternal(): void {
        Quickshell.execDetached(["xdg-open", root.path]);
    }

    function handleKey(event: var): bool {
        switch (event.key) {
        case Qt.Key_Space:
        case Qt.Key_Escape:
            root.back();
            return true;
        case Qt.Key_Left:
            root.step(-1);
            return true;
        case Qt.Key_Right:
            root.step(1);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.openExternal();
            return true;
        case Qt.Key_P:
            body.item?.togglePause?.();
            return true;
        }
        return false;
    }

    // ── Header ──
    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.cfg.previewHeaderHeight

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
            anchors.leftMargin: root.cfg.gap
            anchors.right: count.left
            anchors.rightMargin: root.cfg.gap
            anchors.verticalCenter: parent.verticalCenter
            text: root.fileName
            color: root.theme.islandFg
            font.pixelSize: root.theme.fontSizeClock
            font.weight: Font.DemiBold
            elide: Text.ElideMiddle
        }
        Text {
            id: count
            anchors.right: openBtn.left
            anchors.rightMargin: root.cfg.gap
            anchors.verticalCenter: parent.verticalCenter
            visible: root.index >= 0 && root.files.length > 1
            text: `${root.index + 1} / ${root.files.length}`
            color: root.theme.subtleFg
            font.pixelSize: root.theme.fontSizeBody
            font.features: { "tnum": 1 }
        }
        IconButton {
            id: openBtn
            theme: root.theme
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: header.height
            height: header.height
            glyph: ""
            onClicked: root.openExternal()
        }
    }

    // ── Body ── (rebuilt for every file: a step to a file of the same kind
    // reuses this view, and the bodies load their file once)
    onPathChanged: {
        body.active = false;
        body.active = true;
    }
    Loader {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: root.cfg.gap
        anchors.bottom: parent.bottom
        sourceComponent: root.kind === "image" || root.kind === "animated" || root.kind === "pdf" ? imageComp
            : root.kind === "video" || root.kind === "audio" ? mediaComp
            : textComp
    }

    Component {
        id: imageComp
        Item {
            id: imgBox
            // PDF: first page rendered once per file (cached next to the
            // tile thumbs, regenerated when the file is newer).
            readonly property string pdfPng: `/tmp/pillshell_stash_thumbs/${Qt.md5(root.path)}-ql.png`
            property string pdfReady: ""
            readonly property real naturalW: img.status === Image.Ready ? Math.max(img.implicitWidth, img.sourceSize.width) : 0
            readonly property real naturalH: img.status === Image.Ready ? Math.max(img.implicitHeight, img.sourceSize.height) : 0
            readonly property string src: root.kind === "pdf" ? root.pdfUrl(pdfReady) : root.stash.urlOf(root.path)

            Process {
                running: root.kind === "pdf"
                command: ["bash", "-c", `f=${root.stash.shq(imgBox.pdfPng)}; [ "$f" -nt ${root.stash.shq(root.path)} ] && exit 0; `
                    + `mkdir -p /tmp/pillshell_stash_thumbs && pdftoppm -png -singlefile -f 1 -l 1 -scale-to ${Math.round(root.cfg.previewMaxHeight * 2)} `
                    + `${root.stash.shq(root.path)} "\${f%.png}"`]
                onExited: code => {
                    if (code === 0)
                        imgBox.pdfReady = imgBox.pdfPng;
                }
            }
            AnimatedImage {
                id: img
                anchors.fill: parent
                source: imgBox.src
                playing: root.kind === "animated"
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
                smooth: true
                mipmap: true
            }
        }
    }
    function pdfUrl(file: string): string {
        return file === "" ? "" : root.stash.urlOf(file);
    }

    Component {
        id: mediaComp
        StashPreviewMedia {
            path: root.path
            video: root.kind === "video"
            stash: root.stash
            cfg: root.cfg
            theme: root.theme
        }
    }

    Component {
        id: textComp
        StashPreviewText {
            path: root.path
            kind: root.kind
            stash: root.stash
            cfg: root.cfg
            theme: root.theme
        }
    }
}
