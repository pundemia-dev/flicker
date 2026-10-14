import QtQuick
import QtQuick.Shapes
import "ColorMath.js" as ColorMath
import "../../../config"

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
            root.actions.copyText(panel.valueText, I18n.tr("Color copied"));
        else if (root.liveColor)
            root.actions.copyText(ColorMath.format(root.liveColor.r, root.liveColor.g, root.liveColor.b, panel.initialFmt()), I18n.tr("Color copied"));
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

    // Ready = image loaded AND the Canvas has a context (getContext before
    // `available` only warns and returns null).
    function samplerLoaded(): void {
        if (!sampler.available || !sampler.isImageLoaded(root.srcUrl))
            return;
        root.samplerReady = true;
        if (root.cursorX >= 0)
            root.moveTo(root.cursorX, root.cursorY);
    }

    // Live chip rect in this item's coords — the panel grows out of it.
    function chipRect(): var {
        if (!liveChip.visible || loupe.opacity < 0.5)
            return { x: root.cursorX, y: root.cursorY, w: 1, h: 1 };
        const p = liveChip.mapToItem(root, 0, 0);
        return { x: p.x, y: p.y, w: liveChip.width, h: liveChip.height };
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
        // An image already in the pixmap cache (the backdrop / editor loaded
        // it — e.g. Tab from shot mode) loads synchronously and NEVER emits
        // imageLoaded: check right after loadImage, or picks stay dead.
        Component.onCompleted: {
            loadImage(root.srcUrl);
            root.samplerLoaded();
        }
        onImageLoaded: root.samplerLoaded()
        onAvailableChanged: root.samplerLoaded()
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

    // 1:1 physical grab, only the lens texture source (hideSource).
    Image {
        id: grab
        width: root.physW
        height: root.physH
        source: root.srcUrl
        smooth: false
        sourceSize.width: root.physW
        sourceSize.height: root.physH
    }

    // ── Magnifier loupe ─────────────────────────────────────────────
    Item {
        id: loupe
        readonly property int zoom: root.cfg.loupeZoom
        // Hidden via opacity, never `visible`: a CurveRenderer Shape toggled
        // via visible never repaints once shown again.
        opacity: root.hovered && !panel.hovering && root.cursorX >= 0 ? 1 : 0
        width: root.cfg.loupeSize
        height: width
        x: Math.min(root.cursorX + root.cfg.toolSpacing * 2, root.width - width - root.cfg.toolSpacing)
        // Above the cursor: the chasing square sits right-below it.
        y: Math.max(root.cfg.toolSpacing, root.cursorY - height - root.cfg.toolSpacing * 2)

        // Lens: a ShaderEffectSource cuts the few grab pixels under the
        // cursor (sourceRect, texture = region size, nearest filtering) and a
        // CurveRenderer circle is filled with it (antialiased edge). A
        // zoom-sized Image (physW × zoom ≈ 20k px) inside a clip/layer rendered
        // NOTHING here, not even its siblings.
        readonly property int span: Math.ceil(width / zoom)
        // On-screen size of one grab pixel (= zoom when it divides the size).
        readonly property real texel: width / span
        readonly property int px: Math.round(root.cursorX * root.dpr)
        readonly property int py: Math.round(root.cursorY * root.dpr)

        ShaderEffectSource {
            id: lens
            anchors.fill: parent
            // opacity, not visible: an invisible ShaderEffectSource never
            // renders its texture → the fillItem Shape drew nothing.
            opacity: 0
            sourceItem: grab
            hideSource: true
            smooth: false
            // Picked pixel centred: its centre (p + 0.5) on the lens centre.
            sourceRect: Qt.rect(loupe.px + 0.5 - loupe.span / 2, loupe.py + 0.5 - loupe.span / 2, loupe.span, loupe.span)
            textureSize: Qt.size(loupe.span, loupe.span)
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                strokeColor: "transparent"
                fillColor: root.theme.islandBg
                PathRectangle {
                    width: loupe.width
                    height: loupe.height
                    radius: loupe.width / 2
                }
            }
            ShapePath {
                strokeWidth: -1
                strokeColor: "transparent"
                fillColor: "white"
                fillItem: lens
                // fillItem paints the texture at its NATURAL size (span×span
                // px from the shape origin, edge texels clamped beyond) — the
                // lens showed the sample's bottom-right corner in the centre.
                fillTransform: PlanarTransform.fromScale(loupe.texel, loupe.texel)
                PathRectangle {
                    width: loupe.width
                    height: loupe.height
                    radius: loupe.width / 2
                }
            }
        }

        // Centre cell = the pixel that will be picked.
        Rectangle {
            width: loupe.texel
            height: loupe.texel
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
