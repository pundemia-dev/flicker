import QtQuick
import "../../../components"

// On/off control (Wi‑Fi, Bluetooth, DND, mic, record...). Layout per form:
//   small     whole circle tints with the accent, glyph centred
//   wide      icon disc left (tints), title + status right
//   tall      icon disc on top, title (2 lines) at the bottom
//   large /   icon disc top-left, title + status bottom-left
//   panorama
// The tap action is the user's `activate()` (QsCard calls it).
Item {
    id: root
    property var card: null
    property string glyph: ""
    property string title: ""
    property string subtitle: ""
    property bool on: false
    property color accent: theme?.qsBlue ?? "#0A84FF"
    property var activate: null

    readonly property var theme: root.card?.theme ?? null
    readonly property var cfg: root.card?.cfg ?? null
    readonly property string form: root.card?.form ?? "small"
    readonly property real pad: (root.cfg?.padding) ?? 12
    readonly property real unit: (root.cfg?.unit) ?? 80
    // Icon disc: 1-unit-tall cards fit it to the height, others to a
    // unit minus padding (so it lines up with neighbouring 1x1 circles).
    readonly property real disc: root.form === "small" ? root.width : root.unit - 2 * root.pad

    // Spring-driven on factor: colours mix by it (no timed transitions).
    property real onP: root.on ? 1 : 0
    Behavior on onP { Spring { stiffness: 5; damp: 0.5; eps: 0.01 } }

    function mix(a: color, b: color, t: real): color {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);
    }
    readonly property color idleDisc: root.card?.frost?.layerColor(root.theme?.qsDisc ?? "#3A3A3C") ?? (root.theme?.qsDisc ?? "#3A3A3C")
    readonly property color discColor: root.mix(root.form === "small" ? Qt.rgba(0, 0, 0, 0) : root.idleDisc, root.accent, root.onP)

    Rectangle {
        id: disc
        width: root.disc
        height: root.disc
        radius: width / 2
        color: root.discColor
        x: root.form === "small" || root.form === "tall" ? (root.width - width) / 2 : root.pad
        y: root.form === "small" ? 0 : root.form === "wide" ? (root.height - height) / 2 : root.pad

        Icon {
            anchors.centerIn: parent
            text: root.glyph
            font.family: root.theme?.iconFamily ?? "tabler-icons"
            iconSize: (root.cfg?.iconSize) ?? 22
            iconColor: "white"
        }
    }

    Column {
        id: label
        visible: root.form !== "small"
        spacing: 1
        // wide: right of the disc, vertically centred; tall: bottom, centred;
        // large/panorama: bottom-left.
        // tall: a 1-unit column — near-full width so words fit unbroken.
        readonly property real inset: root.form === "tall" ? 4 : root.pad
        x: root.form === "wide" ? disc.x + disc.width + root.pad * 0.75 : inset
        width: root.width - x - inset
        y: root.form === "wide" ? (root.height - height) / 2 : root.height - height - root.pad

        Text {
            width: parent.width
            text: root.title
            color: "white"
            font.pixelSize: root.form === "tall" ? ((root.cfg?.subtitleSize) ?? 11) : ((root.cfg?.titleSize) ?? 13)
            font.weight: Font.DemiBold
            horizontalAlignment: root.form === "tall" ? Text.AlignHCenter : Text.AlignLeft
            wrapMode: root.form === "tall" ? Text.WordWrap : Text.NoWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            visible: root.form !== "tall" && root.subtitle.length > 0
            text: root.subtitle
            color: root.theme?.cardDim ?? "#99EBEBF5"
            font.pixelSize: (root.cfg?.subtitleSize) ?? 11
            elide: Text.ElideRight
        }
    }
}
