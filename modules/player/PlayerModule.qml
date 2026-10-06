import QtQuick
import QtQuick.Shapes
import Quickshell.Services.Mpris
import "../../components"
import "../../config"

// Player module: full-height cover on the left (rounded like dashboard
// cards); right column = track title (bold) + artist with the lyrics button
// beside that block, pinned to the TOP edge; transport buttons attached with
// a gap above the progress block (bar + elapsed / remaining), which is
// pinned to the BOTTOM edge. Position ticking follows the documented
// MprisPlayer pattern: reads are live, but positionChanged must be emitted
// manually while playing — hence the 1s Timer.
//
// Module content stays press-transparent (spec): close is a swipe-up handled
// by GestureZones below this content; only small controls accept presses.
Item {
    id: root
    required property var players
    property var theme: null
    property var haptics: null
    property var cfg: null
    // Island corner radius: the backdrop fills the whole module and the
    // island's clip is rectangular, so the art rounds itself.
    property real surfaceRadius: 0
    signal closeRequested

    readonly property var player: players.active
    readonly property bool playing: player?.playbackState === MprisPlaybackState.Playing
    readonly property real length: player?.length ?? 0
    // lengthSupported false makes `length` mirror position (no real duration).
    readonly property bool lengthKnown: (player?.lengthSupported ?? false) && root.length > 0
    readonly property real position: player?.position ?? 0
    // Play/pause glyph: tabler filled (pause f690 play f691). Prev/next are
    // shape-built SkipBtn triangles, not a font glyph.
    readonly property string iconFamily: root.theme?.iconFamily ?? "tabler-icons"

    Timer {
        interval: 1000
        repeat: true
        running: root.playing
        onTriggered: {
            if (root.player)
                root.player.positionChanged();
        }
    }

    function sharedSlot(key: string): var {
        return key === "cover" ? coverSlot : null;
    }

    function fmtTime(s: real): string {
        if (!(s > 0))
            return "0:00";
        const m = Math.floor(s / 60);
        const sec = Math.floor(s % 60);
        return `${m}:${sec < 10 ? "0" : ""}${sec}`;
    }

    // Backdrop (MediaCard pattern): the album art, heavily blurred, fills
    // the island; a dark left-to-right scrim keeps the text legible.
    // Track change crossfades the backdrop (no scale: it fills the
    // rectangular-clipped island, anything > 1 would poke out the corners).
    CrossfadeImage {
        anchors.fill: parent
        radius: root.surfaceRadius
        source: root.players.artUrl
        blur: 1
        exitFade: false
        stiffness: 2
        damp: 0.5
    }
    Rectangle {
        anchors.fill: parent
        radius: root.surfaceRadius
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#66000000" }
            GradientStop { position: 1; color: "#A6000000" }
        }
    }

    Row {
        anchors.fill: parent
        // 12 -> 21: module-edge to content gap (spec: x1.75).
        anchors.margins: 16
        spacing: 14

        // Cover slot (shared element "cover", see core/TransitionLayer):
        // the bar's album cover flies in and docks here. The module's own
        // cover is the fallback for opens without a flight (IPC, hover on
        // a collapsed indicator) and hides while an element is docked.
        Item {
            id: coverSlot
            width: parent.height
            height: parent.height
            // Corner radius the flying cover morphs to ("slot" contract).
            readonly property real radius: root.cfg?.cardRadius ?? 13
            property Item docked: null

            // Track change: the new cover pops in from 0.85 with a small
            // spring bounce over the old one shrinking away.
            CrossfadeImage {
                id: cover
                anchors.fill: parent
                visible: coverSlot.docked === null
                radius: coverSlot.radius
                source: root.players.artUrl
                fallbackColor: "#2B2F36"
                fallbackGlyph: "♫"
                glyphSize: 32
                enterScale: 0.85
                exitScale: 0.92
            }
        }

        Item {
            id: info
            width: parent.width - coverSlot.width - parent.spacing
            height: parent.height

            // Title + artist block, lyrics button to its right — pinned to
            // the top edge (the leftover space gathers above the transport).
            Row {
                anchors.top: parent.top
                anchors.left: parent.left
                width: parent.width
                spacing: 10

                Column {
                    width: parent.width - lyricsBtn.width - parent.spacing
                    spacing: 2

                    Text {
                        width: parent.width
                        text: root.players.trackTitle.length > 0 ? root.players.trackTitle : I18n.tr("Not Playing")
                        color: "#F0F4FB"
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: root.players.trackArtist
                        color: "#B3EBEBF5"
                        font.pixelSize: 14
                        elide: Text.ElideRight
                    }
                }

                // Lyrics toggle: placeholder only — a layout change (lyrics
                // view) comes later; source decided: lrclib.net via curl
                // (Weather fetch pattern). No action wired yet.
                Rectangle {
                    id: lyricsBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: 42
                    height: 42
                    radius: 21
                    color: lyricsMa.containsMouse ? "#40FFFFFF" : "#26FFFFFF"

                    Text {
                        id: lyricsLabel
                        anchors.centerIn: parent
                        text: "\ufebc"
                        color: "#DFE6F2"
                        font.family: root.iconFamily
                        font.pixelSize: 20
                    }
                    MouseArea {
                        id: lyricsMa
                        anchors.fill: parent
                        hoverEnabled: true
                    }
                }
            }

            // Transport attached with a gap above the progress block, which
            // is pinned to the bottom edge.
            Column {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                spacing:6

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10

                    SkipBtn {
                        direction: -1
                        triSize: 14
                        dimmed: !root.players.canGoPrevious
                        onClicked: root.players.previous()
                    }
                    TransportBtn {
                        glyph: root.playing ? "\uf690" : "\uf691"
                        glyphSize: 34
                        glyphScaleY: 1.1
                        swapAnimate: true
                        iconFamily: root.iconFamily
                        dimmed: !root.players.canTogglePlaying
                        onClicked: root.players.playPause()
                    }
                    SkipBtn {
                        direction: 1
                        triSize: 14
                        dimmed: !root.players.canGoNext
                        onClicked: root.players.next()
                    }
                }

                Column {
                    width: parent.width
                    spacing: 8

                    // Seekable: press/drag scrubs, release seeks (SeekBar).
                    SeekBar {
                        id: seek
                        width: parent.width
                        height: 8
                        player: root.player
                        haptics: root.haptics
                        position: root.position
                        length: root.length
                        lengthKnown: root.lengthKnown
                    }

                    Item {
                        width: parent.width
                        height: elapsedText.height

                        Text {
                            id: elapsedText
                            anchors.left: parent.left
                            text: root.fmtTime(seek.shownPosition)
                            color: seek.labelColor
                            font.pixelSize: 12
                        }
                        Text {
                            anchors.right: parent.right
                            text: root.lengthKnown ? `-${root.fmtTime(Math.max(0, root.length - seek.shownPosition))}` : "—"
                            color: seek.labelColor
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }
    }
}
