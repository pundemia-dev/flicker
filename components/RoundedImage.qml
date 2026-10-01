import QtQuick
import QtQuick.Effects

// Image clipped to a rounded rectangle (pShell CoverArt pattern: MultiEffect
// with a layer-enabled rounded-rect maskSource — Item clip is square-only).
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
    readonly property bool ready: image.status === Image.Ready

    Image {
        id: image
        anchors.fill: parent
        source: root.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
        // Decode-side downscale to ~2x display size (CPU, high quality):
        // GPU-only minification of a large source shimmers with grain,
        // especially through the MultiEffect sampler (no mipmaps there).
        smooth: true
        mipmap: true
        sourceSize: Qt.size(Math.max(1, Math.ceil(root.width * 2)), Math.max(1, Math.ceil(root.height * 2)))
    }

    // Rounded-rect mask rendered to a texture for MultiEffect (invisible).
    Item {
        id: mask
        anchors.fill: parent
        layer.enabled: true
        visible: false

        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: "white"
        }
    }

    MultiEffect {
        anchors.fill: parent
        source: image
        maskEnabled: true
        maskSource: mask
        visible: root.ready
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
