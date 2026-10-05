import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../../components"

// One tray file (pShell StashDelegate port): theme icon underneath, image /
// PDF / video thumbnail on top once ready, name label (always without a
// thumb, on hover over a dark gradient with one). Hover shows a trash
// button; hovering the trash slides send + bookmark out of it. Dragging the
// tile drags the file out (native text/uri-list drag).
Item {
    id: root
    required property int index
    required property string fileName
    required property string filePath
    required property string fileUrl
    required property bool isFav
    required property var stash
    required property var localSend
    required property var cfg
    required property var theme
    required property real radius
    signal sendRequested(var files)

    readonly property string ext: root.fileName.includes(".") ? root.fileName.split(".").pop().toLowerCase() : ""
    readonly property bool isImage: ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg"].includes(root.ext)
    readonly property bool isPdf: root.ext === "pdf"
    readonly property bool isVideo: ["mp4", "mkv", "avi", "mov", "webm"].includes(root.ext)
    readonly property bool isAudio: ["mp3", "wav", "flac", "ogg", "aac", "m4a", "opus"].includes(root.ext)
    readonly property bool isText: ["txt", "md", "log", "csv", "json", "xml", "toml", "yaml", "yml", "sh", "py", "js", "ts", "rs", "go", "cpp", "c", "h", "qml"].includes(root.ext)
    readonly property bool isArchive: ["zip", "tar", "gz", "bz2", "xz", "rar", "7z", "zst"].includes(root.ext)
    readonly property string themeIcon: root.isImage ? "image-x-generic"
        : root.isPdf ? "application-pdf"
        : root.isVideo ? "video-x-generic"
        : root.isAudio ? "audio-x-generic"
        : root.isText ? "text-x-generic"
        : root.isArchive ? "application-x-archive" : "application-x-generic"

    // Generated thumbs (PDF first page / video frame) are cached by name.
    // Keyed by a path hash (a sanitized name made every Cyrillic name of
    // the same length collide); regenerated when the file is newer.
    readonly property string thumbFile: `/tmp/pillshell_stash_thumbs/${Qt.md5(root.filePath)}.png`
    property string genThumb: ""
    readonly property string thumbSource: root.isImage ? root.fileUrl : (root.genThumb !== "" ? "file://" + root.genThumb : "")
    readonly property bool hasThumb: thumb.ready && root.thumbSource !== ""
    readonly property bool hovered: tileMa.containsMouse || actionsHover.hovered

    Component.onCompleted: if (root.isPdf || root.isVideo) thumbGen.running = true

    Process {
        id: thumbGen
        command: ["bash", "-c", `f=${root.stash.shq(root.thumbFile)}; [ "$f" -nt ${root.stash.shq(root.filePath)} ] && exit 0; mkdir -p /tmp/pillshell_stash_thumbs; `
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
        Drag.mimeData: ({ "text/uri-list": root.fileUrl })
        // Pins the tray (Stash.outgoingDrag): the island ignores it as an
        // incoming drop and never closes the module under the drag.
        Drag.onDragStarted: root.stash.outgoingDrag = true
        Drag.onDragFinished: {
            root.stash.outgoingDrag = false;
            dragItem.x = 0;
            dragItem.y = 0;
        }
    }

    // ── Actions: trash, then send + bookmark born from under it ──
    Item {
        id: actions
        readonly property real btn: root.cfg.tileButtonSize
        readonly property real gap: 4
        // Latched by hovering the trash, released when the strip is left.
        property bool expanded: false
        readonly property bool shown: root.hovered && !root.stash.outgoingDrag

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 5
        // Fixed (expanded) width: growing it would shift every button's
        // local x and the springs would make the trash jump.
        width: actions.btn * 3 + actions.gap * 2
        height: actions.btn

        HoverHandler {
            id: actionsHover
            onHoveredChanged: if (!hovered) actions.expanded = false
        }

        TileButton {
            id: trashBtn
            slot: 0
            glyph: ""
            onHoveredChanged: if (hovered) actions.expanded = true
            onClicked: root.stash.remove(root.filePath)
        }
        TileButton {
            slot: 1
            available: root.localSend.enabled
            glyph: ""
            accent: true
            onClicked: root.sendRequested([root.filePath])
        }
        TileButton {
            slot: root.localSend.enabled ? 2 : 1
            glyph: ""
            checked: root.isFav
            onClicked: root.stash.toggleFav(root.index)
        }
    }

    // Small square glyph button; slot 0 = trash (rightmost). Slots > 0 sit
    // behind the trash until the strip expands, then spring out leftwards.
    component TileButton: Rectangle {
        id: tb
        property int slot: 0
        property string glyph
        property bool accent: false
        property bool checked: false
        // Use this, not `visible` (that would override the fade-out gate and
        // leave an invisible, clickable button behind the trash).
        property bool available: true
        readonly property bool hovered: tbMa.containsMouse
        readonly property bool isOut: tb.available && (tb.slot === 0 ? actions.shown : actions.shown && actions.expanded)
        signal clicked

        width: actions.btn
        height: actions.btn
        radius: Math.min(8, root.radius / 2)
        x: actions.width - actions.btn - (tb.isOut ? tb.slot * (actions.btn + actions.gap) : 0)
        z: -tb.slot
        color: tb.accent ? root.theme.cardBlue
            : tb.checked ? Qt.alpha(root.theme.cardBlue, 0.55)
            : (tb.hovered ? root.theme.cardTrack : Qt.rgba(0.11, 0.11, 0.12, 0.92))
        opacity: tb.isOut ? 1 : 0
        scale: tb.isOut ? 1 : 0.5
        visible: opacity > 0.01
        Behavior on x { Spring { stiffness: 5; damp: 0.4 } }
        Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
        Behavior on scale { Spring { stiffness: 5; damp: 0.4; eps: 0.005 } }

        Text {
            anchors.centerIn: parent
            text: tb.glyph
            color: root.theme.islandFg
            font.family: root.theme.iconFamily
            font.pixelSize: Math.round(actions.btn * 0.55)
        }
        MouseArea {
            id: tbMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tb.clicked()
        }
    }
}
