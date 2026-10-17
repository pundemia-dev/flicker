import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../../components"
import "StashTypes.js" as Types

// One tray file (pShell StashDelegate port): theme icon underneath, image /
// PDF / video thumbnail on top once ready, name label (always without a
// thumb, on hover over a dark gradient with one). Hover shows ONE menu
// button; a click turns it into the action panel (StashTileMenu: send,
// favourite, transcribe for audio / video, open, delete). Dragging the tile drags the file out (native
// text/uri-list drag). A transcription shows as a thin bar at the bottom
// (running / queued) or a text badge top-left (done).
// Selection (Stash.selection): Ctrl+click toggles, Shift+click adds the
// range from the last toggled tile, a plain click toggles while anything
// is selected; selected = accent ring + check badge (every tile shows an
// empty circle while selecting). Dragging a SELECTED tile drags the whole
// selection. Double click = Quick Look.
Item {
    id: root
    required property int index
    required property string fileName
    required property string filePath
    required property string fileUrl
    required property bool isFav
    required property bool isDir
    required property var stash
    required property var localSend
    required property var cfg
    required property var theme
    required property real radius
    signal sendRequested(var files)
    signal transcribeRequested(string file)
    signal menuRequested(Item button)
    signal previewRequested(string file)
    // The tray's DropExpand (the menu button stays out while it is open).
    property var menu: null
    readonly property Item menuButton: menuBtn
    readonly property color menuButtonColor: Qt.rgba(0.11, 0.11, 0.12, 0.92)

    readonly property string kind: Types.kindOf(root.fileName, root.isDir)
    readonly property bool isImage: root.kind === "image" || root.kind === "animated"
    readonly property bool isPdf: root.kind === "pdf"
    readonly property bool isVideo: root.kind === "video"
    readonly property bool isAudio: root.kind === "audio"
    readonly property string themeIcon: Types.themeIcon(root.kind)
    readonly property bool selected: root.stash.selection[root.filePath] === true
    readonly property bool selecting: root.stash.selectedCount > 0

    // Generated thumbs (PDF first page / video frame) are cached by name.
    // Keyed by a path hash (a sanitized name made every Cyrillic name of
    // the same length collide); regenerated when the file is newer.
    readonly property string thumbFile: `/tmp/flicker_stash_thumbs/${Qt.md5(root.filePath)}.png`
    property string genThumb: ""
    readonly property string thumbSource: root.isImage ? root.fileUrl : (root.genThumb !== "" ? "file://" + root.genThumb : "")
    readonly property bool hasThumb: thumb.ready && root.thumbSource !== ""
    readonly property bool hovered: tileMa.containsMouse || actionsHover.hovered || menuMa.containsMouse
    readonly property bool canTranscribe: root.isAudio || root.isVideo
    readonly property var tr: root.stash.transcribe
    // Re-read on every Transcribe change (stateOf is a function).
    readonly property string trState: {
        if (!root.canTranscribe)
            return "";
        root.tr.known; root.tr.queue; root.tr.current; root.tr.errors;
        return root.tr.stateOf(root.filePath);
    }

    Component.onCompleted: if (root.isPdf || root.isVideo) thumbGen.running = true

    Process {
        id: thumbGen
        command: ["bash", "-c", `f=${root.stash.shq(root.thumbFile)}; [ "$f" -nt ${root.stash.shq(root.filePath)} ] && exit 0; mkdir -p /tmp/flicker_stash_thumbs; `
            + (root.isPdf
                ? `pdftoppm -r 80 -singlefile -png -l 1 ${root.stash.shq(root.filePath)} "\${f%.png}"`
                : `ffmpeg -v error -y -ss 1 -i ${root.stash.shq(root.filePath)} -frames:v 1 -vf scale=256:-1 "$f"`)]
        onExited: code => {
            if (code === 0)
                root.genThumb = root.thumbFile;
        }
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: root.radius
        color: root.theme.cardBg

        IconImage {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -8
            implicitSize: Math.min(parent.width, parent.height) * 0.5
            source: Quickshell.iconPath(root.themeIcon, "application-x-generic")
            asynchronous: true
            opacity: root.hasThumb ? 0 : 1
        }

        RoundedImage {
            id: thumb
            anchors.fill: parent
            radius: root.radius
            source: root.thumbSource
            opacity: root.hasThumb ? 1 : 0
            Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
        }

        // Dark gradient behind the hover label (thumbs only).
        Rectangle {
            anchors.fill: parent
            radius: root.radius
            visible: root.hasThumb
            opacity: root.hovered ? 1 : 0
            Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
            gradient: Gradient {
                GradientStop { position: 0.35; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.75) }
            }
        }

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 6
            text: root.fileName
            color: root.hasThumb ? "white" : root.theme.subtleFg
            font.pixelSize: root.theme.fontSizeTiny
            elide: Text.ElideMiddle
            horizontalAlignment: Text.AlignHCenter
            opacity: !root.hasThumb || root.hovered ? 1 : 0
            Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
        }
    }

    // ── Transcription state ──
    ProgressBar {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 6
        height: 3
        visible: root.trState === "running" || root.trState === "queued"
        value: root.trState === "running" ? root.tr.progress : 0
        trackColor: Qt.rgba(0, 0, 0, 0.55)
        fillColor: root.theme.cardBlue
    }
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 5
        width: root.cfg.tileButtonSize
        height: root.cfg.tileButtonSize
        radius: Math.min(8, root.radius / 2)
        visible: !root.selecting && (root.trState === "done" || root.trState === "error")
        color: root.trState === "error" ? Qt.alpha(root.theme.accentRed, 0.85) : Qt.rgba(0.11, 0.11, 0.12, 0.92)
        Text {
            anchors.centerIn: parent
            text: root.trState === "error" ? "\uea06" : "\ueaa2"
            color: root.theme.islandFg
            font.family: root.theme.iconFamily
            font.pixelSize: Math.round(root.cfg.tileButtonSize * 0.55)
        }
    }

    // ── Selection: accent ring + check badge (empty circle while selecting) ──
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: 2
        border.color: root.theme.cardBlue
        opacity: root.selected ? 1 : 0
        Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
    }
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 5
        width: root.cfg.tileButtonSize
        height: width
        radius: width / 2
        color: root.selected ? root.theme.cardBlue : Qt.rgba(0, 0, 0, 0.45)
        border.width: root.selected ? 0 : 1.5
        border.color: Qt.rgba(1, 1, 1, 0.8)
        opacity: root.selecting ? 1 : 0
        scale: root.selecting ? 1 : 0.5
        visible: opacity > 0.01
        Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
        Behavior on scale { Spring { stiffness: 5; damp: 0.4; eps: 0.005 } }
        Text {
            anchors.centerIn: parent
            text: "\uea5e"
            color: "white"
            font.family: root.theme.iconFamily
            font.pixelSize: Math.round(parent.width * 0.62)
            opacity: root.selected ? 1 : 0
        }
    }

    // ── Drag out ──
    // Drag.active is set imperatively ONCE past the threshold: binding it to
    // drag.active is re-entrant with Drag.Automatic (the native drag drops
    // the grab, the binding re-runs inside QDrag::exec and frees the
    // QMimeData mid-drag — pShell segfault).
    MouseArea {
        id: tileMa
        anchors.fill: parent
        hoverEnabled: true
        drag.target: dragItem
        cursorShape: Qt.OpenHandCursor

        onClicked: mouse => {
            if (mouse.modifiers & Qt.ShiftModifier)
                root.stash.selectRange(root.filePath);
            else if ((mouse.modifiers & Qt.ControlModifier) || root.selecting)
                root.stash.toggleSelect(root.filePath);
        }
        onDoubleClicked: mouse => {
            if (!(mouse.modifiers & (Qt.ShiftModifier | Qt.ControlModifier)) && !root.selecting)
                root.previewRequested(root.filePath);
        }

        readonly property bool armed: drag.active
        // Released before the image grab landed: no native drag started,
        // put the drag proxy back.
        onReleased: {
            if (!dragItem.Drag.active) {
                dragItem.x = 0;
                dragItem.y = 0;
            }
        }
        onArmedChanged: {
            if (!armed || dragItem.Drag.active)
                return;
            surface.grabToImage(result => {
                if (!tileMa.drag.active)
                    return;
                dragItem.Drag.imageSource = result.url;
                dragItem.Drag.active = true;
            });
        }
    }

    Item {
        id: dragItem
        width: root.width
        height: root.height
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction
        Drag.proposedAction: Qt.CopyAction
        // A selected tile carries the whole selection.
        Drag.mimeData: ({ "text/uri-list": root.selected && root.stash.selectedCount > 1
                ? root.stash.selectedPaths().map(p => root.stash.urlOf(p)).join("\r\n")
                : root.fileUrl })
        // Pins the tray (Stash.outgoingDrag): the island ignores it as an
        // incoming drop and never closes the module under the drag.
        Drag.onDragStarted: root.stash.outgoingDrag = true
        Drag.onDragFinished: {
            root.stash.outgoingDrag = false;
            dragItem.x = 0;
            dragItem.y = 0;
        }
    }

    // ── Menu: one button on hover; a click turns it into the action panel
    // (components/DropExpand owned by the tray, StashTileMenu inside) ──
    Rectangle {
        id: menuBtn
        readonly property bool menuOpen: root.menu?.active === true && root.menu.source === menuBtn
        readonly property bool isOut: (root.hovered && !root.stash.outgoingDrag) || menuBtn.menuOpen
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 5
        width: root.cfg.tileButtonSize
        height: root.cfg.tileButtonSize
        radius: Math.min(8, root.radius / 2)
        color: menuMa.containsMouse ? root.theme.cardTrack : root.menuButtonColor
        opacity: menuBtn.isOut ? 1 : 0
        scale: menuBtn.isOut ? 1 : 0.5
        visible: opacity > 0.01
        Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
        Behavior on scale { Spring { stiffness: 5; damp: 0.4; eps: 0.005 } }

        HoverHandler {
            id: actionsHover
        }
        Text {
            anchors.centerIn: parent
            text: "\uea95"
            color: root.theme.islandFg
            font.family: root.theme.iconFamily
            font.pixelSize: Math.round(root.cfg.tileButtonSize * 0.6)
        }
        MouseArea {
            id: menuMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.menuRequested(menuBtn)
        }
    }
}
