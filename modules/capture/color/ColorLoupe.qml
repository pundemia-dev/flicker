import QtQuick
import QtQuick.Effects
import "ColorMath.js" as ColorMath

// Colour-pick mode on one screen (port of pShell ColorLoupe): circular
// magnifier over the frozen grab, pixels sampled synchronously through a
// 1×1 Immediate Canvas (no per-move process). A click opens ColorPanel
// (result + formats + HSL editor) without leaving the picker; further
// clicks re-pick. Enter copies (picked colour, else the live one) and closes.
Item {
    id: root
    required property var capture
    required property var actions
    required property var theme
    required property var cfg
    required property string screenName
    required property real ox
    required property real oy
    required property real dpr
    required property string srcPath
    required property Item keyTarget

    readonly property string srcUrl: "file://" + root.srcPath
    readonly property int physW: Math.round(width * dpr)
    readonly property int physH: Math.round(height * dpr)

    // ── Tool contract (CaptureOverlay) ──────────────────────────────
    readonly property var cutRect: null
    readonly property bool dimmed: false
    readonly property bool hasSelection: false

    property real cursorX: -1
    property real cursorY: -1
    readonly property bool hovered: ma.containsMouse
    property var liveColor: null
    property bool samplerReady: false

    function handleEscape(): bool {
        if (panel.open) {
            panel.open = false;
            return true;
        }
        return false;
    }

    function handleKey(event: var): bool {
        return false;
    }

    function confirm(): void {
        if (panel.fieldFocused)
            return;
        if (panel.open)
            root.actions.copyText(panel.valueText, "Цвет скопирован");
        else if (root.liveColor)
            root.actions.copyText(ColorMath.format(root.liveColor.r, root.liveColor.g, root.liveColor.b, panel.initialFmt()), "Цвет скопирован");
        root.capture.done();
    }

    function sampleAt(lx: real, ly: real): var {
        if (!root.samplerReady)
            return null;
        const px = Math.max(0, Math.min(Math.round(lx * root.dpr), root.physW - 1));
        const py = Math.max(0, Math.min(Math.round(ly * root.dpr), root.physH - 1));
        const ctx = sampler.getContext("2d");
        if (!ctx)
            return null;
        ctx.clearRect(0, 0, 1, 1);
        ctx.drawImage(root.srcUrl, px, py, 1, 1, 0, 0, 1, 1);
        const d = ctx.getImageData(0, 0, 1, 1).data;
        return { r: d[0], g: d[1], b: d[2] };
    }

    function moveTo(x: real, y: real): void {
        root.cursorX = x;
        root.cursorY = y;
        root.capture.pointerAt(root.ox + x, root.oy + y);
        const c = root.sampleAt(x, y);
        if (c)
            root.liveColor = c;
    }

    Canvas {
        id: sampler
        width: 1
        height: 1
        opacity: 0
        renderStrategy: Canvas.Immediate
        renderTarget: Canvas.Image
        Component.onCompleted: loadImage(root.srcUrl)
        onImageLoaded: {
            root.samplerReady = true;
            if (root.cursorX >= 0)
                root.moveTo(root.cursorX, root.cursorY);
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.CrossCursor
        onEntered: root.moveTo(mouseX, mouseY)
        onPositionChanged: mouse => root.moveTo(mouse.x, mouse.y)
        onWheel: wheel => root.capture.cycle(wheel.angleDelta.y > 0 ? -1 : 1)
        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) {
                root.capture.cancel();
                return;
            }
            const c = root.sampleAt(mouse.x, mouse.y);
            if (c) {
                root.capture.claim(root.screenName);
                panel.show(c.r, c.g, c.b);
            }
        }
    }

    // ── Magnifier loupe ─────────────────────────────────────────────
    Item {
        id: loupe
        readonly property int zoom: root.cfg.loupeZoom
        visible: root.hovered && !panel.hovering && root.cursorX >= 0
        width: root.cfg.loupeSize
        height: width
        x: Math.min(root.cursorX + root.cfg.toolSpacing * 2, root.width - width - root.cfg.toolSpacing)
        // Above the cursor: the chasing square sits right-below it.
        y: Math.max(root.cfg.toolSpacing, root.cursorY - height - root.cfg.toolSpacing * 2)

        // Circular crop: the island clip trick does not apply here (Item
        // clip is rectangular) — binary MultiEffect mask, its stair-step is
        // hidden under the 2px ring drawn on top.
        Item {
            id: lens
            anchors.fill: parent
            clip: true
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: lensMask
                autoPaddingEnabled: false
            }

            Rectangle {
                anchors.fill: parent
                color: root.theme.islandBg
            }

            Image {
                source: root.srcUrl
                smooth: false
                sourceSize.width: root.physW
                sourceSize.height: root.physH
                width: root.physW * loupe.zoom
                height: root.physH * loupe.zoom
                x: loupe.width / 2 - root.cursorX * root.dpr * loupe.zoom
                y: loupe.height / 2 - root.cursorY * root.dpr * loupe.zoom
            }
        }

        Item {
            id: lensMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "white"
            }
        }

        // Centre cell = the pixel that will be picked.
        Rectangle {
            width: loupe.zoom
            height: loupe.zoom
            x: (loupe.width - width) / 2
            y: (loupe.height - height) / 2
            color: "transparent"
            border.width: 1
            border.color: root.theme.islandFg
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: root.theme.islandFg
        }

        // Live value chip under the loupe.
        Rectangle {
            id: liveChip
            anchors.top: parent.bottom
            anchors.topMargin: root.cfg.toolSpacing
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.liveColor !== null
            width: chipRow.implicitWidth + root.cfg.panelPad
            height: chipRow.implicitHeight + root.cfg.toolSpacing
            radius: height / 2
            color: root.theme.islandBg

            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: root.cfg.toolSpacing
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: hexText.implicitHeight
                    height: width
                    radius: width / 2
                    color: root.liveColor ? Qt.rgba(root.liveColor.r / 255, root.liveColor.g / 255, root.liveColor.b / 255, 1) : "transparent"
                    border.width: 1
                    border.color: root.theme.cardTrack
                }
                Text {
                    id: hexText
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.theme.islandFg
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fontSizeBody
                    font.features: { "tnum": 1 }
                    text: root.liveColor ? ColorMath.toHex(root.liveColor.r, root.liveColor.g, root.liveColor.b) : ""
                }
            }
        }
    }

    ColorPanel {
        id: panel
        anchors.fill: parent
        picker: root
    }
}
