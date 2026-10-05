import QtQuick
import "../../components"
import "../../config"

// iOS-style OSD (volume / mic / brightness): the whole island is one big
// capsule slider (pShell BatteryTank pattern, horizontal): the fill springs
// to the value, split from the track by a gap with rounded inner edges; the
// level glyph sits inside on the left, the number inside on the right.
// Both are drawn twice — light over the empty track, dark ink inside the
// fill (clipped to it) — so they stay legible
// wherever the fill edge crosses them. Payload: { kind: "volume"|"mic"|
// "brightness"|"custom", push (-1/0/+1: the press hit an end), value + icon
// (custom only) }. Known kinds bind the LIVE service value — PipeWire
// applies a volume set asynchronously, a snapshot at key time lags a step.
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
    readonly property string valueText: muted ? "0" : `${Math.round(value * 100)}`

    readonly property color lightInk: root.theme?.islandFg ?? "#E9ECF1"
    readonly property color dimInk: root.theme?.subtleFg ?? "#B9C0CB"
    readonly property color darkInk: root.theme?.islandBg ?? "#000000"
    readonly property color fillColor: root.boosted ? (root.theme?.accentOrange ?? "#E58B4D") : root.lightInk

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
    // bar toward that end and springs back. Every press is a fresh payload
    // object, so repeats re-trigger.
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

    // Glyph change pops in from a smaller scale (spring); both ink copies
    // share it.
    property real iconScale: 1
    onGlyphChanged: if (root.settled) iconPop.restart()
    Spring {
        id: iconPop
        target: root
        property: "iconScale"
        from: root.cfg.iconPopFrom
        to: 1
        stiffness: root.cfg.fillStiffness
        damp: root.cfg.fillDamping
        eps: 0.002
    }

    property real fillAnim: root.fill
    Behavior on fillAnim {
        Spring {
            stiffness: root.cfg.fillStiffness
            damp: root.cfg.fillDamping
            eps: 0.001
        }
    }

    Item {
        id: barBox
        anchors.fill: parent
        anchors.margins: root.cfg.inset

        RoundedClip {
            id: bar
            // Stretch grows the bar toward the pushed end and thins it a
            // touch, like an elastic band.
            width: barBox.width * (1 + Math.abs(root.stretch))
            height: barBox.height * (1 - Math.abs(root.stretch) * 1.5)
            x: root.stretch < 0 ? -(width - barBox.width) : 0
            anchors.verticalCenter: parent.verticalCenter
            // Concentric with the island: island radius minus the inset.
            radius: Math.max(0, (Config.data.modules?.osd?.radius ?? Config.data.island.radius) - root.cfg.inset)

            // Fill and track are two pieces split by a gap, both rounded
            // on the inner edge (outer ends = the bar's own clip). The gap
            // fades in/out near the ends so 0% / 100% stay one solid piece.
            readonly property real fillW: bar.width * root.fillAnim
            readonly property real gapW: root.cfg.gap
                * Math.max(0, Math.min(1, fillW / root.cfg.gap, (bar.width - fillW) / root.cfg.gap))

            Rectangle {
                x: bar.fillW + bar.gapW
                width: Math.max(0, bar.width - x)
                height: parent.height
                radius: Math.min(root.cfg.innerRadius, width / 2)
                color: root.theme?.cardTrack ?? "#2C2C2E"
            }
            Ink {
                inkColor: root.muted ? root.dimInk : root.lightInk
            }
            Item {
                width: Math.max(0, bar.fillW)
                height: bar.height
                clip: true

                Rectangle {
                    anchors.fill: parent
                    radius: Math.min(root.cfg.innerRadius, width / 2)
                    color: root.fillColor
                }
                Ink {
                    inkColor: root.darkInk
                }
            }
        }
    }

    // Glyph left + number right, laid out in bar coordinates.
    component Ink: Item {
        id: ink
        property color inkColor
        width: bar.width
        height: bar.height

        Text {
            anchors.left: parent.left
            anchors.leftMargin: root.cfg.padding
            anchors.verticalCenter: parent.verticalCenter
            width: root.cfg.iconSize
            horizontalAlignment: Text.AlignHCenter
            text: root.glyph
            color: ink.inkColor
            scale: root.iconScale
            font.family: root.kind === "custom" ? (root.theme?.fontFamily ?? "SF Pro Display") : (root.theme?.iconFamily ?? "tabler-icons")
            font.pixelSize: root.cfg.iconSize
        }
        RollingText {
            anchors.right: parent.right
            anchors.rightMargin: root.cfg.padding
            anchors.verticalCenter: parent.verticalCenter
            text: root.valueText
            color: ink.inkColor
            pixelSize: root.cfg.valueSize
            weight: Font.DemiBold
            family: root.theme?.fontFamily ?? "SF Pro Display"
        }
    }
}
