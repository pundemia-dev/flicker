import QtQuick
import Quickshell.Services.Mpris
import "../../../components"
import "../../player"
import "MediaLayout.js" as MediaLayout
import "../../../config"

// Now playing, one layout that MORPHS between footprints (MediaLayout.js):
//   1x1  cover fills the circle (dimmed) + play
//   2x1  cover disc + play/next      4x1  + title, prev
//   2x2  cover top-left, output top-right, title, transport at the bottom
//   4x2  the player module layout (cover left, title + output, transport,
//        progress) at card scale (user: same as the player)
//   4x4  cover half-height + title beside, progress, big transport, volume
//        (4x4 / 4x6 edge inset = twice the 4x2 margin)
//   4x6  full-width cover, title + output, progress, big transport, volume
// (volume = system output, like iOS Now Playing; no OSD — audio.quiet())
// Every element lives in every layout: on resize each rect springs to its
// new target (cover shrinks, transport travels under it), elements the
// layout lacks leave/arrive through FadeBlur. Targets come from the TARGET
// footprint (not the animated card size), so they share the card's spring.
// Buttons are the player's own (TransportBtn / SkipBtn). The output button
// (where the lyrics button sits in the player) opens the audio panel
// (panels/AudioPanel: outputs, inputs, mixer) out of itself through the
// QS expander (`openOutput(button)`). 4x4 / 4x6: output joins the transport row
// (right of next) as a bare grey glyph, a like button (placeholder, MPRIS
// has no rating API) appears left of prev, and a 6-bar audio visualizer
// (AudioBars, cava) takes the output button's old spot.
// Tap outside the buttons = `activate()` (opens the player where the card
// has no progress block).
Item {
    id: root
    property var card: null
    property var players: null
    property var audio: null
    property var haptics: null
    property var activate: null
    // (source item) → opens the audio panel from it (QsCardFactory).
    property var openOutput: null
    readonly property Item outputButton: outBtn
    // Output button glyph: headphones / display when the sound goes there,
    // else the cast glyph.
    readonly property string outputGlyph: {
        const sink = root.audio?.sink ?? null;
        const n = `${sink?.name ?? ""} ${sink?.description ?? ""}`;
        if (/bluez|head(phone|set)/i.test(n))
            return "\ueabd";
        if (/hdmi|displayport/i.test(n))
            return "\uea89";
        return "\uea56";
    }

    readonly property var theme: root.card?.theme ?? null
    readonly property var cfg: root.card?.cfg ?? null
    readonly property int cols: root.card?.spanW ?? 1
    readonly property int rows: root.card?.spanH ?? 1
    readonly property real unit: (root.cfg?.unit) ?? 80
    readonly property real spacing: (root.cfg?.spacing) ?? 12
    readonly property string iconFamily: root.theme?.iconFamily ?? "tabler-icons"

    readonly property var player: root.players?.active ?? null
    readonly property bool hasPlayer: root.player !== null
    readonly property bool playing: root.player?.playbackState === MprisPlaybackState.Playing
    readonly property real length: root.player?.length ?? 0
    readonly property bool lengthKnown: (root.player?.lengthSupported ?? false) && root.length > 0
    readonly property real position: root.player?.position ?? 0

    readonly property var lay: MediaLayout.layout({
        w: root.cols * root.unit + (root.cols - 1) * root.spacing,
        h: root.rows * root.unit + (root.rows - 1) * root.spacing,
        cols: root.cols,
        rows: root.rows,
        k: (root.cfg?.playerScale) ?? 1,
        unit: root.unit,
        pad: (root.cfg?.padding) ?? 12,
        radius: root.card?.radius ?? 36
    })
    readonly property bool hasProgress: root.lay.progress.show

    // MprisPlayer pattern: position reads are live, positionChanged must be
    // emitted manually while playing.
    Timer {
        interval: 1000
        repeat: true
        running: root.playing && root.hasProgress
        onTriggered: root.player?.positionChanged()
    }

    function fmtTime(s: real): string {
        if (!(s > 0))
            return "0:00";
        const m = Math.floor(s / 60);
        const sec = Math.floor(s % 60);
        return `${m}:${sec < 10 ? "0" : ""}${sec}`;
    }

    // Backdrop (player pattern): blurred art + dark left-to-right scrim.
    CrossfadeImage {
        anchors.fill: parent
        radius: root.card?.radius ?? 36
        source: root.players?.artUrl ?? ""
        blur: 1
        exitFade: false
        stiffness: 2
        damp: 0.5
    }
    Rectangle {
        anchors.fill: parent
        radius: root.card?.radius ?? 36
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#66000000" }
            GradientStop { position: 1; color: "#A6000000" }
        }
    }

    CrossfadeImage {
        id: cover
        x: root.lay.cover.x
        y: root.lay.cover.y
        width: root.lay.cover.s
        height: root.lay.cover.s
        radius: root.lay.cover.r
        opacity: root.lay.cover.dim && root.hasPlayer ? 0.55 : 1
        source: root.players?.artUrl ?? ""
        fallbackColor: root.theme?.qsDisc ?? "#3A3A3C"
        fallbackGlyph: root.lay.cover.dim ? "" : "♫"
        glyphSize: Math.round(width * 0.4)
        enterScale: 0.85
        exitScale: 0.92
        Behavior on x { Spring {} }
        Behavior on y { Spring {} }
        Behavior on width { Spring {} }
        Behavior on height { Spring {} }
        Behavior on radius { Spring {} }
        Behavior on opacity { Spring { eps: 0.01 } }
    }

    FadeBlur {
        shown: root.lay.title.show
        blurMax: 16
        x: root.lay.title.x
        y: root.lay.title.y
        width: root.lay.title.w
        height: col.height
        Behavior on x { Spring {} }
        Behavior on y { Spring {} }
        Behavior on width { Spring {} }

        Column {
            id: col
            width: parent.width
            spacing: 2

            Text {
                width: parent.width
                text: root.hasPlayer && (root.players?.trackTitle ?? "") !== "" ? root.players.trackTitle : I18n.tr("Not Playing")
                color: "#F0F4FB"
                font.pixelSize: root.lay.titleSize
                font.weight: Font.Bold
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: root.players?.trackArtist ?? ""
                color: "#B3EBEBF5"
                font.pixelSize: root.lay.titleSize
                elide: Text.ElideRight
            }
        }
    }

    // Glyph ink: light on a disc, secondary grey when bare (4x4 / 4x6).
    readonly property color inkLight: "#DFE6F2"
    readonly property color inkGrey: "#99EBEBF5"
    readonly property color inkHover: "#F0F4FB"
    function mix(a: color, b: color, t: real): color {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
            a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);
    }

    // Audio output button → the audio panel. Glyph = the current output.
    FadeBlur {
        id: outBtn
        shown: root.lay.out.show
        blurMax: 12
        x: root.lay.out.x
        y: root.lay.out.y
        width: root.lay.outSize
        height: root.lay.outSize
        Behavior on x { Spring {} }
        Behavior on y { Spring {} }

        // 0 = disc + light glyph, 1 = bare grey glyph.
        property real bare: root.lay.out.bare ? 1 : 0
        Behavior on bare { Spring { eps: 0.01 } }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "white"
            opacity: (outMa.containsMouse ? 0.25 : 0.15) * (1 - outBtn.bare)
        }
        Text {
            anchors.centerIn: parent
            text: root.outputGlyph
            color: root.mix(root.inkLight, outMa.containsMouse ? root.inkHover : root.inkGrey, outBtn.bare)
            font.family: root.iconFamily
            font.pixelSize: Math.round(parent.width * 0.48)
            scale: root.lay.out.bare ? root.lay.sideScale : 1
            Behavior on scale { Spring { eps: 0.005 } }
        }
        MouseArea {
            id: outMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !(root.card?.editing ?? false)
            onClicked: root.openOutput?.(outBtn)
        }
    }

    // Like (placeholder, no action yet): bare grey heart left of prev.
    FadeBlur {
        shown: root.lay.like.show
        blurMax: 12
        x: root.lay.like.cx - root.lay.outSize / 2
        y: root.lay.like.cy - root.lay.outSize / 2
        width: root.lay.outSize
        height: root.lay.outSize
        Behavior on x { Spring {} }
        Behavior on y { Spring {} }

        Text {
            anchors.centerIn: parent
            text: ""
            color: likeMa.containsMouse ? root.inkHover : root.inkGrey
            font.family: root.iconFamily
            font.pixelSize: Math.round(parent.width * 0.48 * root.lay.sideScale)
        }
        MouseArea {
            id: likeMa
            anchors.fill: parent
            hoverEnabled: true
        }
    }

    // Audio visualizer on the output button's old spot (4x4 / 4x6).
    FadeBlur {
        shown: root.lay.viz.show
        blurMax: 12
        x: root.lay.viz.x
        y: root.lay.viz.y
        width: root.lay.outSize
        height: root.lay.outSize
        Behavior on x { Spring {} }
        Behavior on y { Spring {} }

        AudioBars {
            anchors.centerIn: parent
            width: Math.round(parent.width * 0.62)
            height: parent.height
            // Only while shown on the visible tab and something plays.
            active: root.lay.viz.show && root.playing && root.visible
            color: "#F0F4FB"
        }
    }

    // Transport: the player's own buttons, each slot springs to its centre.
    component Slot: FadeBlur {
        property var at: ({ cx: 0, cy: 0, show: false })
        shown: at.show
        blurMax: 12
        width: root.lay.box
        height: root.lay.box
        // From the TARGET box, not the animated width: a target that moves
        // every frame restarts the x spring each frame (it crawls).
        x: at.cx - root.lay.box / 2
        y: at.cy - root.lay.box / 2
        Behavior on x { Spring {} }
        Behavior on y { Spring {} }
        Behavior on width { Spring {} }
        Behavior on height { Spring {} }
    }
    Slot {
        at: root.lay.buttons.prev
        SkipBtn {
            anchors.centerIn: parent
            direction: -1
            boxSize: parent.width
            triSize: root.lay.tri
            dimmed: !(root.players?.canGoPrevious ?? false)
            onClicked: root.players?.previous()
        }
    }
    Slot {
        at: root.lay.buttons.play
        TransportBtn {
            anchors.centerIn: parent
            boxSize: parent.width
            glyph: root.playing ? "" : ""
            glyphSize: root.lay.glyph
            glyphScaleY: 1.1
            swapAnimate: true
            iconFamily: root.iconFamily
            dimmed: !(root.players?.canTogglePlaying ?? false)
            onClicked: root.players?.playPause()
        }
    }
    Slot {
        at: root.lay.buttons.next
        SkipBtn {
            anchors.centerIn: parent
            direction: 1
            boxSize: parent.width
            triSize: root.lay.tri
            dimmed: !(root.players?.canGoNext ?? false)
            onClicked: root.players?.next()
        }
    }

    // Progress bar + elapsed / remaining (player layout).
    FadeBlur {
        shown: root.lay.progress.show
        blurMax: 16
        x: root.lay.progress.x
        y: root.lay.progress.y
        width: root.lay.progress.w
        height: prog.height
        Behavior on x { Spring {} }
        Behavior on y { Spring {} }
        Behavior on width { Spring {} }

        Column {
            id: prog
            width: parent.width
            spacing: root.lay.barGap

            // Seekable like the player module (SeekBar).
            SeekBar {
                id: seek
                width: parent.width
                height: root.lay.bar
                player: root.player
                haptics: root.haptics
                position: root.position
                length: root.length
                lengthKnown: root.lengthKnown
            }
            Item {
                width: parent.width
                height: elapsed.height

                Text {
                    id: elapsed
                    anchors.left: parent.left
                    text: root.fmtTime(seek.shownPosition)
                    color: seek.labelColor
                    font.pixelSize: root.lay.timesSize
                }
                Text {
                    anchors.right: parent.right
                    text: root.lengthKnown ? `-${root.fmtTime(Math.max(0, root.length - seek.shownPosition))}` : "—"
                    color: seek.labelColor
                    font.pixelSize: root.lay.timesSize
                }
            }
        }
    }

    // System volume row (4x4 / 4x6): speaker · bar · speaker (size: MediaLayout volIcon). Press sets
    // the value where it lands, drag follows (local value while dragging:
    // PipeWire applies volume async).
    FadeBlur {
        id: vol
        shown: root.lay.volume.show
        blurMax: 16
        x: root.lay.volume.x
        y: root.lay.volume.y
        width: root.lay.volume.w
        height: root.lay.volH
        Behavior on x { Spring {} }
        Behavior on y { Spring {} }
        Behavior on width { Spring {} }

        readonly property real max: root.audio?.maxVolume ?? 1
        readonly property real live: (root.audio?.muted ?? false) ? 0 : (root.audio?.volume ?? 0) / max
        property real dragValue: 0
        readonly property real shownValue: volMa.pressed ? dragValue : Math.max(0, Math.min(1, live))

        // Speakers (VolumeIcon): the left one is always arc-less and bumps
        // when the volume reaches 0 (slash while muted); the right one
        // always shows three arcs and plays the wave on reaching 100%.
        // The bar spans 0..maxVolume (> 1), so "100%" is checked on the
        // real volume, not on the bar fraction.
        readonly property real shownVolume: vol.shownValue * vol.max
        property real lastVolume: -1
        onShownVolumeChanged: {
            if (vol.lastVolume >= 0) {
                if (vol.shownVolume <= 0.001 && vol.lastVolume > 0.001)
                    volLow.pulse();
                else if (vol.shownVolume >= 0.999 && vol.lastVolume < 0.999)
                    volHigh.wave();
            }
            vol.lastVolume = vol.shownVolume;
        }
        VolumeIcon {
            id: volLow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            size: root.lay.volIcon
            maxArcs: 0
            arcs: 0
            muted: root.audio?.muted ?? false
            color: "#B3EBEBF5"
        }
        VolumeIcon {
            id: volHigh
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            size: root.lay.volIcon
            arcs: 3
            color: "#B3EBEBF5"
        }
        ProgressBar {
            id: volBar
            anchors.left: volLow.right
            anchors.right: volHigh.left
            anchors.leftMargin: root.lay.volGap
            anchors.rightMargin: root.lay.volGap
            anchors.verticalCenter: parent.verticalCenter
            height: root.lay.bar
            value: vol.shownValue
            trackColor: "#33FFFFFF"
            fillColor: "#F0F4FB"
        }
        MouseArea {
            id: volMa
            // Full row height over the bar: a 7px bar alone is hard to hit.
            x: volBar.x
            width: volBar.width
            height: parent.height
            function setAt(mx: real): void {
                vol.dragValue = Math.max(0, Math.min(1, mx / width));
                root.audio?.quiet();
                root.audio?.setVolume(vol.dragValue * vol.max);
            }
            onPressed: mouse => setAt(mouse.x)
            onPositionChanged: mouse => setAt(mouse.x)
            onWheel: wheel => {
                vol.dragValue = vol.shownValue;
                setAt((vol.shownValue + (wheel.angleDelta.y > 0 ? 1 : -1) * ((root.cfg?.wheelStep) ?? 0.05)) * width);
            }
        }
    }
}
