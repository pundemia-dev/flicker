import QtQuick
import "../../../components"

// Default Quick Settings button template (Wi‑Fi, Bluetooth, DND, mic,
// record, screenshot...). Three footprints only (QsCatalog.BUTTON_SIZES):
//   1x1 small  glyph centred, nothing else
//   2x1 wide   bare glyph left (no disc), text block right
//   2x2 large  bare glyph top-left, text block bottom-left
// Text block = title + status. The status line exists only for toggles
// (`toggle: true`, default): `status` defaults to Вкл./Выкл. and a card
// may pass its own (SSID, timer...). One-shot actions set `toggle: false`
// and show the title alone. "On" tints the whole card with `accent`.
// The tap action is the user's `activate()` (QsCard calls it).
Item {
    id: root
    property var card: null
    property string glyph: ""
    property string title: ""
    property bool toggle: true
    property bool on: false
    property string status: root.on ? "Вкл." : "Выкл."
    property color accent: theme?.qsBlue ?? "#0A84FF"
    property var activate: null

    readonly property var theme: root.card?.theme ?? null
    readonly property var cfg: root.card?.cfg ?? null
    readonly property string form: root.card?.form ?? "small"
    readonly property real pad: (root.cfg?.padding) ?? 12
    readonly property real unit: (root.cfg?.unit) ?? 80
    readonly property real iconSize: (root.cfg?.buttonIconSize) ?? 33
    // Glyph centre sits where a 1x1 card's would (unit/2 from the edges),
    // so wide/large glyphs line up with neighbouring circles and stay
    // concentric with the card's corner rounding.
    readonly property real iconCentre: root.unit / 2
    // Large: text shares the glyph's left edge, mirrored bottom inset.
    readonly property real largeInset: root.iconCentre - root.iconSize / 2
    readonly property bool showStatus: root.toggle && root.status.length > 0

    // Spring-driven on factor: colours mix by it (no timed transitions).
    property real onP: root.toggle && root.on ? 1 : 0
    Behavior on onP { Spring { stiffness: 5; damp: 0.5; eps: 0.01 } }

    function mix(a: color, b: color, t: real): color {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);
    }

    Rectangle {
        anchors.fill: parent
        radius: root.card?.radius ?? root.unit / 2
        color: root.accent
        opacity: root.onP
    }

    Icon {
        width: root.iconSize
        height: root.iconSize
        x: root.form === "small" ? (root.width - width) / 2 : root.iconCentre - width / 2
        y: root.form === "small" || root.form === "wide" ? (root.height - height) / 2 : root.iconCentre - height / 2
        text: root.glyph
        font.family: root.theme?.iconFamily ?? "tabler-icons"
        iconSize: root.iconSize
        iconColor: "white"
    }

    Column {
        visible: root.form !== "small"
        spacing: 1
        x: root.form === "wide" ? root.iconCentre + root.iconSize / 2 + root.pad : root.largeInset
        width: root.width - x - (root.form === "wide" ? root.pad : root.largeInset)
        y: root.form === "wide" ? (root.height - height) / 2 : root.height - height - root.largeInset

        Text {
            width: parent.width
            text: root.title
            color: "white"
            font.pixelSize: (root.cfg?.titleSize) ?? 13
            font.weight: Font.DemiBold
            wrapMode: root.form === "wide" ? Text.NoWrap : Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            visible: root.showStatus
            text: root.status
            // Dim grey on the dark card, translucent white on the accent.
            color: root.mix(root.theme?.cardDim ?? "#99EBEBF5", Qt.rgba(1, 1, 1, 0.8), root.onP)
            font.pixelSize: (root.cfg?.subtitleSize) ?? 11
            elide: Text.ElideRight
        }
    }
}
