import QtQuick
import "../../../components"

// Now playing. Layout per form:
//   small     cover fills the circle (dimmed), play/pause glyph on top
//   wide      cover disc left; 2x1: play + next, 4x1: title/artist + prev/play/next
//   large     cover top-left, title/artist under it, controls along the bottom
//   panorama  big cover left, title/artist + controls right
// Tap on the card (outside the buttons) = `activate()` (opens the player).
Item {
    id: root
    property var card: null
    property var players: null
    property var activate: null

    readonly property var theme: root.card?.theme ?? null
    readonly property var cfg: root.card?.cfg ?? null
    readonly property string form: root.card?.form ?? "small"
    readonly property int spanW: root.card?.spanW ?? 1
    readonly property real pad: (root.cfg?.padding) ?? 12
    readonly property real unit: (root.cfg?.unit) ?? 72
    readonly property bool hasPlayer: (root.players?.active ?? null) !== null
    readonly property bool playing: root.players?.musicActive ?? false
    readonly property string titleText: root.hasPlayer && (root.players?.trackTitle ?? "") !== "" ? root.players.trackTitle : "Не воспроизводится"
    readonly property string artistText: root.hasPlayer ? (root.players?.trackArtist ?? "") : ""

    readonly property real coverSize: {
        if (root.form === "small")
            return root.width;
        if (root.form === "panorama")
            return root.height - 2 * root.pad;
        return root.unit - 2 * root.pad;
    }

    RoundedImage {
        id: cover
        width: root.coverSize
        height: root.coverSize
        x: root.form === "small" ? 0 : root.pad
        y: root.form === "small" ? 0 : root.form === "wide" ? (root.height - height) / 2 : root.pad
        radius: root.form === "small" || root.form === "wide" ? width / 2 : 12
        source: root.players?.artUrl ?? ""
        opacity: root.form === "small" && root.hasPlayer ? 0.55 : 1

        // Own fallback: RoundedImage's glyph is not in the icon font.
        Rectangle {
            anchors.fill: parent
            z: -1
            radius: cover.radius
            visible: !cover.ready && root.form !== "small"
            color: root.theme?.qsDisc ?? "#3A3A3C"

            Icon {
                anchors.centerIn: parent
                text: "\ueafc"
                font.family: root.theme?.iconFamily ?? "tabler-icons"
                iconSize: Math.round(parent.width * 0.42)
                iconColor: root.theme?.cardDim ?? "#99EBEBF5"
            }
        }
    }

    Column {
        id: label
        visible: root.form === "large" || root.form === "panorama" || (root.form === "wide" && root.spanW >= 4)
        spacing: 1
        x: root.form === "large" ? root.pad : cover.x + cover.width + root.pad * 0.75
        y: root.form === "large" ? cover.y + cover.height + 6 : root.form === "wide" ? (root.height - height) / 2 : root.pad + 2
        width: (root.form === "wide" ? controls.x - 6 : root.width - root.pad) - x

        Text {
            width: parent.width
            text: root.titleText
            color: "white"
            font.pixelSize: (root.cfg?.titleSize) ?? 13
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            visible: text.length > 0
            text: root.artistText
            color: root.theme?.cardDim ?? "#99EBEBF5"
            font.pixelSize: (root.cfg?.subtitleSize) ?? 11
            elide: Text.ElideRight
        }
    }

    Row {
        id: controls
        readonly property bool withPrev: root.form !== "wide" || root.spanW >= 4
        readonly property real btn: root.form === "small" ? root.width : 32
        spacing: root.form === "large" ? Math.max(0, (root.width - 2 * root.pad - 3 * btn) / 2) : 4
        x: {
            if (root.form === "small")
                return 0;
            if (root.form === "wide")
                return root.width - width - root.pad;
            if (root.form === "large")
                return root.pad;
            return label.x - 6;
        }
        y: {
            if (root.form === "small")
                return 0;
            if (root.form === "wide")
                return (root.height - height) / 2;
            return root.height - height - root.pad;
        }

        MediaButton { visible: controls.withPrev && root.form !== "small"; glyph: ""; onClicked: root.players?.previous() }
        MediaButton { glyph: root.playing ? "" : ""; big: root.form === "small"; onClicked: root.players?.playPause() }
        MediaButton { visible: root.form !== "small"; glyph: ""; onClicked: root.players?.next() }
    }

    component MediaButton: Item {
        id: btn
        property string glyph: ""
        property bool big: false
        signal clicked
        width: controls.btn
        height: controls.btn
        opacity: root.hasPlayer ? 1 : 0.4

        Icon {
            anchors.centerIn: parent
            text: btn.glyph
            font.family: root.theme?.iconFamily ?? "tabler-icons"
            iconSize: btn.big ? 26 : 20
            iconColor: "white"
            scale: ma.pressed ? 0.85 : 1
            Behavior on scale { Spring { stiffness: 6; damp: 0.4; eps: 0.01 } }
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            enabled: root.hasPlayer
            onClicked: btn.clicked()
            onPressAndHold: root.card?.holdRequested()
        }
    }
}
