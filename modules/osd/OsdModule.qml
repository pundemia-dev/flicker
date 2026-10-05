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

    // Volume uses the shape-built VolumeIcon (arcs follow the level, slash
    // on mute); the glyph covers the other kinds.
    // Bound to the SINK itself, not to the current kind: the (hidden)
    // speaker must not follow mic mute/level while the OSD shows the mic,
    // or switching back replays a slash/arc change.
    readonly property bool sinkMuted: !!audio?.muted
    readonly property real sinkFill: sinkMuted ? 0 : Math.min(1, Math.max(0, audio?.volume ?? 0))
    readonly property int volumeArcs: sinkFill <= 0.001 ? 0 : sinkFill < 1 / 3 ? 1 : sinkFill < 2 / 3 ? 2 : 3
    readonly property string glyph: {
        if (kind === "volume")
            return "";
        if (kind === "mic")
            return muted ? "" : "";          // microphone(-off)
        if (kind === "brightness")
            return value < 0.5 ? "\uD800\uDD07" : "\uD800\uDD08";    // sun-low-filled / sun-high-filled (U+10107/8)
        return payload?.icon ?? "";
    }

    // Rubber band (iOS): a press that cannot move the value stretches the
    // bar toward that end and springs back. Every press is a fresh payload
    // object, so repeats re-trigger.
    property real stretch: 0
    property bool settled: false
    Component.onCompleted: root.settled = true
    // VolumeIcon accents (both ink copies listen): reaching 0 (or pushing
    // below it) bumps the icon, reaching 100% (or pushing past it) runs the
    // speaker -> arcs wave.
    signal volumePulse
    signal volumeWave
    // Tracks the sink, not `fill` (which jumps on a mic <-> volume switch).
    property real lastFill: -1
    onSinkFillChanged: {
        if (root.kind === "volume" && root.settled && root.lastFill >= 0) {
            if (root.sinkFill <= 0.001 && root.lastFill > 0.001)
                root.volumePulse();
            else if (root.sinkFill >= 0.999 && root.lastFill < 0.999)
                root.volumeWave();
        }
        root.lastFill = root.sinkFill;
    }
    // Brightness reaching 100% (or pushing past it) bumps the sun glyph.
    property real lastBrightness: -1
    readonly property real brightnessLevel: brightness?.brightness ?? 0
    onBrightnessLevelChanged: {
        if (root.kind === "brightness" && root.settled && root.lastBrightness >= 0
                && root.brightnessLevel >= 0.999 && root.lastBrightness < 0.999)
            glyphBump.bump();
        root.lastBrightness = root.brightnessLevel;
    }
    GlyphBump {
        id: glyphBump
    }
    onPayloadChanged: {
        const push = root.payload?.push ?? 0;
        if (push === 0)
            return;
        if (root.kind === "volume") {
            if (push < 0)
                root.volumePulse();
            else
                root.volumeWave();
        } else if (root.kind === "brightness" && push > 0) {
            glyphBump.bump();
        }
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

        Item {
            anchors.left: parent.left
            anchors.leftMargin: root.cfg.padding
            anchors.verticalCenter: parent.verticalCenter
            width: root.cfg.iconSize
            height: root.cfg.iconSize
            // opacity, NOT visible: toggling `visible` over CurveRenderer
            // Shapes broke rendering (the speaker and even the sibling
            // mic glyph vanished after a volume -> mic kind switch).
            opacity: root.kind === "volume" ? 1 : 0

            // Drawn speaker is ~0.8 of the box height and the 3-arc box is
            // wider than tall: scale up to match the other kinds' glyphs and
            // pin the box to the left padding (fewer arcs = the speaker
            // re-centres inside it).
            VolumeIcon {
                id: volIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                size: root.cfg.iconSize * 1.15
                color: ink.inkColor
                arcs: root.volumeArcs
                muted: root.sinkMuted
            }
            Connections {
                target: root
                function onVolumePulse(): void {
                    volIcon.pulse();
                }
                function onVolumeWave(): void {
                    volIcon.wave();
                }
            }
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: root.cfg.padding
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.kind !== "volume" ? 1 : 0
            width: root.cfg.iconSize
            horizontalAlignment: Text.AlignHCenter
            text: root.glyph
            color: ink.inkColor
            scale: root.iconScale * glyphBump.value
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
