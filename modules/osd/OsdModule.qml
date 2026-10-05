import QtQuick
import "../../components"
import "../../config"

// iOS-style OSD (volume / mic / brightness): level glyph on the left, a fat
// capsule track whose white fill springs to the value, rolling percent on
// the right. Payload: { kind: "volume"|"mic"|"brightness"|"custom",
// push (-1/0/+1: the press hit an end), value + icon (custom only) }.
// Known kinds bind the LIVE service value — PipeWire applies a volume set
// asynchronously, a value snapshotted at key time is one step behind.
Item {
    id: root
    required property var payload
    property var theme: null
    property var audio: null
    property var brightness: null
    signal closeRequested

    readonly property var cfg: Config.data.osd
    readonly property string kind: payload?.kind ?? "custom"
    readonly property real value: Math.max(0, kind === "volume" ? (audio?.volume ?? 0)
        : kind === "mic" ? (audio?.sourceVolume ?? 0)
        : kind === "brightness" ? (brightness?.brightness ?? 0)
        : (payload?.value ?? 0))
    readonly property bool muted: kind === "volume" ? !!audio?.muted
        : kind === "mic" ? !!audio?.sourceMuted : false
    // Audio may exceed 100% (audio.maxVolume): the bar shows 0..100%, the
    // overdrive part tints the fill instead of overflowing the track.
    readonly property real fill: muted ? 0 : Math.min(1, value)
    readonly property bool boosted: !muted && value > 1.001
    readonly property int percent: Math.round(value * 100)

    readonly property string glyph: {
        if (kind === "volume") {
            if (muted || value <= 0.001)
                return "";                         // volume-off
            return value < 0.5 ? "" : "";    // volume-2 / volume
        }
        if (kind === "mic")
            return muted ? "" : "";          // microphone(-off)
        if (kind === "brightness")
            return value < 0.5 ? "" : "";    // sun-low / sun-high
        return payload?.icon ?? "";
    }

    // Rubber band (iOS): a press that cannot move the value stretches the
    // track toward that end and springs back. Every press is a fresh
    // payload object, so repeats re-trigger.
    property real stretch: 0
    property bool settled: false
    Component.onCompleted: root.settled = true
    onPayloadChanged: {
        const push = root.payload?.push ?? 0;
        if (push === 0)
            return;
        stretchAnim.stop();
        root.stretch = push * root.cfg.rubberBand;
        stretchAnim.start();
    }
    Spring {
        id: stretchAnim
        target: root
        property: "stretch"
        to: 0
        stiffness: root.cfg.stretchStiffness
        damp: root.cfg.stretchDamping
        eps: 0.0005
    }

    Item {
        id: iconBox
        anchors.left: parent.left
        anchors.leftMargin: root.cfg.margin
        anchors.verticalCenter: parent.verticalCenter
        width: root.cfg.iconBox
        height: root.cfg.iconBox

        Text {
            id: icon
            anchors.centerIn: parent
            text: root.glyph
            color: root.muted ? (root.theme?.subtleFg ?? "#B9C0CB") : (root.theme?.islandFg ?? "#E9ECF1")
            font.family: root.kind === "custom" ? (root.theme?.fontFamily ?? "SF Pro Display") : (root.theme?.iconFamily ?? "tabler-icons")
            font.pixelSize: root.cfg.iconSize
            // Glyph change pops in from a smaller scale (spring).
            onTextChanged: if (root.settled) iconPop.restart()
        }
        Spring {
            id: iconPop
            target: icon
            property: "scale"
            from: root.cfg.iconPopFrom
            to: 1
            stiffness: root.cfg.fillStiffness
            damp: root.cfg.fillDamping
            eps: 0.002
        }
    }

    RollingText {
        id: valueText
        anchors.right: parent.right
        anchors.rightMargin: root.cfg.margin
        anchors.verticalCenter: parent.verticalCenter
        width: root.cfg.valueWidth
        text: root.muted ? "0" : `${root.percent}`
        color: root.muted ? (root.theme?.subtleFg ?? "#B9C0CB") : (root.theme?.islandFg ?? "#E9ECF1")
        pixelSize: root.cfg.valueSize
        weight: Font.DemiBold
        family: root.theme?.fontFamily ?? "SF Pro Display"
    }

    Item {
        id: trackBox
        anchors.left: iconBox.right
        anchors.leftMargin: root.cfg.spacing
        anchors.right: valueText.left
        anchors.rightMargin: root.cfg.spacing
        anchors.verticalCenter: parent.verticalCenter
        height: root.cfg.trackHeight

        Rectangle {
            id: track
            // Stretch grows the track toward the pushed end (origin on the
            // opposite end) and thins it a touch, like an elastic band.
            width: parent.width * (1 + Math.abs(root.stretch))
            x: root.stretch < 0 ? -(width - parent.width) : 0
            height: parent.height * (1 - Math.abs(root.stretch) * 1.5)
            anchors.verticalCenter: parent.verticalCenter
            radius: height / 2
            color: root.cfg.trackColor
            clip: true

            Rectangle {
                id: fillRect
                height: parent.height
                radius: height / 2
                width: Math.max(0, parent.width * fillAnim)
                color: root.boosted ? (root.theme?.accentOrange ?? "#E58B4D") : (root.theme?.islandFg ?? "#E9ECF1")
                property real fillAnim: root.fill
                Behavior on fillAnim {
                    Spring {
                        stiffness: root.cfg.fillStiffness
                        damp: root.cfg.fillDamping
                        eps: 0.001
                    }
                }
            }
        }
    }
}
