import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

// Image clipped to a rounded rectangle. Painted as an antialiased Shape
// (CurveRenderer, PathRectangle) filled with the image texture via
// ShapePath.fillItem — MultiEffect's mask is a hard alpha threshold here, so
// a mask-based clip left stair-stepped corners. Item clip is square-only.
// Internal rounded fallback (color + glyph) covers empty/failed/loading
// states; the default transparent color + empty glyph render nothing, so
// callers can draw their own fallback behind instead.
Item {
    id: root

    property url source: ""
    property real radius: 0
    property color fallbackColor: "transparent"
    property string fallbackGlyph: ""
    property color glyphColor: "#E8ECF4"
    property int glyphSize: 32
    // Backdrop blur of the art (0..1, MultiEffect blurMax px at 1). The
    // image overscans by blurMax so the blur's transparent fringe falls
    // outside the baked layer and the rounded edge stays solid.
    property real blur: 0
    property int blurMax: 48
    // Ready, or reloading with the previous frame retained (sourceSize step
    // during a resize / shared-element flight): keeps the art on screen
    // instead of blinking to the fallback for every re-decode.
    readonly property bool ready: image.status === Image.Ready
        || (image.status === Image.Loading && root.hadFrame)
    property bool hadFrame: false
    // Raw decode status (CrossfadeImage waits for it to leave Loading).
    readonly property int status: image.status
    onSourceChanged: root.hadFrame = false

    // Decode size: ~2x display, rounded UP to a power of two, so a growing
    // item (shared-element flight 24 -> 138px) re-decodes a few times
    // (64/128/256/512) instead of on every frame.
    function decodeStep(px: real): int {
        return Math.max(16, Math.pow(2, Math.ceil(Math.log(Math.max(1, px * 2)) / Math.LN2)));
    }

    // Layered wrapper = the fill texture: the layer bakes the cropped
    // (PreserveAspectCrop) frame at item size, which a bare Image texture
    // would not (fillItem samples the whole source image).
    Item {
        id: art
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true

        Image {
            id: image
            anchors.fill: parent
            anchors.margins: root.blur > 0 ? -root.blurMax : 0
            visible: root.blur <= 0
            source: root.source
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            // Decode-side downscale to ~2x display size (CPU, high quality):
            // GPU-only minification of a large source shimmers with grain.
            smooth: true
            mipmap: true
            sourceSize: Qt.size(root.decodeStep(root.width), root.decodeStep(root.height))
            // Keep showing the last frame while a new sourceSize decodes.
            retainWhileLoading: true
            onStatusChanged: if (status === Image.Ready) root.hadFrame = true
        }
        MultiEffect {
            anchors.fill: image
            source: image
            visible: root.blur > 0
            blurEnabled: true
            blur: root.blur
            blurMax: root.blurMax
            autoPaddingEnabled: false
        }
    }

    Shape {
        anchors.fill: parent
        visible: root.ready
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillColor: "white"
            fillItem: art

            PathRectangle {
                x: 0
                y: 0
                width: root.width
                height: root.height
                radius: Math.min(root.radius, root.width / 2, root.height / 2)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.fallbackColor
        visible: !root.ready

        Text {
            anchors.centerIn: parent
            text: root.fallbackGlyph
            color: root.glyphColor
            font.pixelSize: root.glyphSize
            visible: root.fallbackGlyph.length > 0
        }
    }
}
