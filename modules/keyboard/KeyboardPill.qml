import QtQuick
import QtQuick.Shapes
import "../../components"

// The keyboard capsule (macOS input-source / Caps Lock indicator, after
// solium's KeyboardPill.qml): ⇪ as an outlined arrow over a bar (drawn, not
// a font glyph) or the layout's short name (letters drum-roll on a quick
// re-switch). Background = the wallpaper accent (Theme.wallAccent, springs
// to a new wallpaper), ink picked for contrast. A soft shadow from stacked
// capsules (no shader). Appears through FadeBlur + a scale pop; its width
// springs between the contents. Position is the overlay's business.
Item {
    id: root
    property bool shown: false
    property string what: "caps"
    property string label: ""
    property color bg: "#E5E5EA"
    property var cfg: ({})
    property var theme: null

    readonly property real pillHeight: cfg.pillHeight ?? 26
    readonly property real padX: cfg.pillPadding ?? 10
    readonly property real capsWidth: cfg.pillCapsWidth ?? 34
    readonly property real margin: cfg.shadowSize ?? 10
    // Light background → dark ink, else white.
    readonly property color ink: (0.2126 * bg.r + 0.7152 * bg.g + 0.0722 * bg.b) > (cfg.inkThreshold ?? 0.6)
        ? (theme?.keyboardPillInkDark ?? "#1C1C1E") : (theme?.keyboardPillInkLight ?? "#FFFFFF")

    TextMetrics {
        id: fm
        font.family: labelText.family
        font.pixelSize: labelText.pixelSize
        font.weight: labelText.weight
        text: root.label
    }
    // Target width (the overlay positions by it, not by the animated one).
    readonly property real targetWidth: root.what === "layout"
        ? Math.max(root.capsWidth, Math.ceil(fm.advanceWidth) + 2 * root.padX) : root.capsWidth
    property real capsuleWidth: root.targetWidth
    Behavior on capsuleWidth { Spring { stiffness: root.cfg.widthSpring ?? 4; damp: root.cfg.widthDamping ?? 0.4 } }

    width: root.capsuleWidth + 2 * root.margin
    height: root.pillHeight + 2 * root.margin

    readonly property real p: fade.p

    FadeBlur {
        id: fade
        anchors.fill: parent
        shown: root.shown
        scale: 1 - (1 - root.p) * (root.cfg.popScale ?? 0.15)

        // Shadow: each ring a pixel wider and fainter outward.
        Repeater {
            model: Math.max(0, root.margin - 2)
            Rectangle {
                id: ring
                required property int index
                readonly property real out: (ring.index + 1) / Math.max(1, root.margin - 2)
                anchors.centerIn: capsule
                anchors.verticalCenterOffset: root.cfg.shadowOffset ?? 3
                width: capsule.width + 2 * (ring.index + 1)
                height: capsule.height + 2 * (ring.index + 1)
                radius: height / 2
                color: Qt.rgba(0, 0, 0, (root.cfg.shadowStrength ?? 0.035) * (1 - ring.out) * (1 - ring.out) + 0.003)
            }
        }

        Rectangle {
            id: capsule
            anchors.centerIn: parent
            width: root.capsuleWidth
            height: root.pillHeight
            radius: height / 2
            color: root.bg
        }

        // ⇪ (16 px design grid, scaled to the capsule).
        FadeBlur {
            anchors.centerIn: capsule
            width: root.pillHeight * (root.cfg.capsGlyph ?? 0.62)
            height: width
            shown: root.what === "caps"

            Shape {
                id: capsShape
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                readonly property real u: width / 16
                ShapePath {
                    strokeColor: root.ink
                    strokeWidth: root.cfg.capsStroke ?? 1.6
                    fillColor: "transparent"
                    joinStyle: ShapePath.RoundJoin
                    capStyle: ShapePath.RoundCap
                    scale: Qt.size(capsShape.u, capsShape.u)
                    startX: 8; startY: 1.2
                    PathLine { x: 14.6; y: 6.8 }
                    PathLine { x: 11; y: 6.8 }
                    PathLine { x: 11; y: 9.2 }
                    PathLine { x: 5; y: 9.2 }
                    PathLine { x: 5; y: 6.8 }
                    PathLine { x: 1.4; y: 6.8 }
                    PathLine { x: 8; y: 1.2 }
                }
                ShapePath {
                    strokeColor: root.ink
                    strokeWidth: root.cfg.capsStroke ?? 1.6
                    fillColor: "transparent"
                    joinStyle: ShapePath.RoundJoin
                    scale: Qt.size(capsShape.u, capsShape.u)
                    PathRectangle { x: 5; y: 12.2; width: 6; height: 2.4; radius: 1 }
                }
            }
        }

        FadeBlur {
            anchors.fill: capsule
            shown: root.what === "layout"

            RollingText {
                id: labelText
                anchors.centerIn: parent
                text: root.label
                color: root.ink
                pixelSize: root.cfg.labelSize ?? 13
                weight: Font.DemiBold
                family: root.theme?.fontFamily ?? "SF Pro Display"
                tabular: false
                renderType: Text.QtRendering
            }
        }
    }
}
