import QtQuick
import QtQuick.Shapes
import Quickshell.Services.Mpris
import "../../components"

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
    property var cfg: null
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

            RoundedImage {
                id: cover
                anchors.fill: parent
                visible: coverSlot.docked === null
                radius: coverSlot.radius
                source: root.players.artUrl
                fallbackColor: "#2B2F36"
                fallbackGlyph: "♫"
                glyphSize: 32
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
                        text: root.players.trackTitle.length > 0 ? root.players.trackTitle : "Ничего не играет"
                        color: "#F0F4FB"
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: root.players.trackArtist
                        color: "#98A4B6"
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
                    color: lyricsMa.containsMouse ? "#39414E" : "#2A303A"

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

                    ProgressBar {
                        width: parent.width
                        height: 8
                        value: root.lengthKnown ? Math.min(1, root.position / root.length) : 0
                    }

                    Item {
                        width: parent.width
                        height: elapsedText.height

                        Text {
                            id: elapsedText
                            anchors.left: parent.left
                            text: root.fmtTime(root.position)
                            color: "#98A4B6"
                            font.pixelSize: 12
                        }
                        Text {
                            anchors.right: parent.right
                            text: root.lengthKnown ? `-${root.fmtTime(Math.max(0, root.length - root.position))}` : "—"
                            color: "#98A4B6"
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }
    }

    // Soft pressed подложка shared by TransportBtn/SkipBtn: radial-gradient
    // disc (solid core, feathered edge) instead of a hard-edged Rectangle.
    // Visible ONLY while pressed — no idle/hover background.
    component PressDisc: Canvas {
        property bool pressed: false
        anchors.fill: parent
        visible: pressed
        onPressedChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            const cx = width / 2, cy = height / 2, r = width / 2;
            ctx.clearRect(0, 0, width, height);
            const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r);
            g.addColorStop(0, "#39414E");
            g.addColorStop(0.85, "#39414E");
            g.addColorStop(1, "transparent");
            ctx.fillStyle = g;
            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, Math.PI * 2);
            ctx.fill();
        }
    }

    // Play/pause transport button: glyph only; the подложка (bg disc) appears
    // ONLY while pressed — no idle/hover background.
    component TransportBtn: Item {
        id: btn
        property string glyph: ""
        property real boxSize: 50
        property real glyphSize: 26
        property real glyphScaleY: 1.0
        // Text-swap pop (tempShell StyledText pattern): when `glyph`
        // changes, scale dips to swapFrom on the accel curve, the new glyph
        // swaps in, scale returns on the decel curve. Deliberate exception
        // to the Spring-only rule (user request).
        property bool swapAnimate: false
        property real swapFrom: 0
        property real swapTo: 1
        property int swapDuration: 400
        property bool dimmed: false
        signal clicked

        width: boxSize
        height: boxSize
        opacity: dimmed ? 0.4 : 1

        PressDisc {
            pressed: btnMa.pressed
        }
        Text {
            id: glyphText
            anchors.centerIn: parent
            text: btn.glyph
            color: "#DFE6F2"
            font.family: root.iconFamily
            font.pixelSize: btn.glyphSize
            transform: Scale {
                yScale: btn.glyphScaleY
                origin.x: glyphText.width / 2
                origin.y: glyphText.height / 2
            }
            Behavior on text {
                enabled: btn.swapAnimate
                SequentialAnimation {
                    NumberAnimation {
                        target: glyphText
                        property: "scale"
                        to: btn.swapFrom
                        duration: btn.swapDuration / 3
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.3, 0, 1, 1, 1, 1]
                    }
                    PropertyAction {}
                    NumberAnimation {
                        target: glyphText
                        property: "scale"
                        to: btn.swapTo
                        duration: btn.swapDuration / 3
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0, 0, 0, 1, 1, 1]
                    }
                }
            }
        }
        MouseArea {
            id: btnMa
            anchors.fill: parent
            onClicked: if (!btn.dimmed)
                btn.clicked()
        }
    }

    // Skip prev/next button built from shapes instead of an icon-font glyph:
    // two rounded triangles pointing the motion way (zero gap) inside a
    // two-triangle-wide track, plus a third triangle staged hidden (scale 0)
    // at the rear slot. Press choreography runs on ONE spring driver
    // (track.p 0 -> 1): the extreme front triangle fades and drives away,
    // the staged one scales up from the rear edge, and the remaining
    // triangle is pushed out by it — its x is bound to the staged
    // triangle's scale, so the scale spring shapes its travel as well. When
    // the spring lands, the roles rotate (front -> staged, staged -> rear,
    // rear -> front) and p resets to 0 within the same frame, so nothing
    // visibly snaps. Rapid re-presses mid-flight are ignored.
    component SkipBtn: Item {
        id: skip
        property int direction: 1 // 1 = next (point right), -1 = prev (point left)
        property real boxSize: 50
        property real triSize: 22 // triangle height, ex-glyph size
        property bool dimmed: false
        signal clicked

        readonly property real triW: skip.triSize * 0.95
        readonly property real triCorner: skip.triSize * 0.12

        width: skip.boxSize
        height: skip.boxSize
        opacity: skip.dimmed ? 0.4 : 1

        function go(): void {
            if (skip.dimmed || fly.running)
                return;
            skip.clicked();
            fly.restart();
        }

        PressDisc {
            pressed: skipMa.pressed
        }

        Item {
            id: track
            property real p: 0
            property int iIn: 2
            property int iRear: 0
            property int iFront: 1

            readonly property real rearSlot: skip.direction > 0 ? 0 : skip.triW
            readonly property real frontSlot: skip.direction > 0 ? skip.triW : 0

            function posFor(idx: int): real {
                const push = frontSlot - rearSlot;
                if (idx === iRear)
                    return rearSlot + push * p;
                if (idx === iFront)
                    return frontSlot + push * 0.55 * p;
                return rearSlot;
            }
            function finishSwap(): void {
                const f = iFront;
                iFront = iRear;
                iRear = iIn;
                iIn = f;
                p = 0;
            }

            width: skip.triW * 2
            height: skip.triSize
            anchors.centerIn: parent

            Spring {
                id: fly
                target: track
                property: "p"
                to: 1
                stiffness: 5
                damp: 0.5
                eps: 0.001
                onFinished: track.finishSwap()
            }

            Shape {
                property int idx: 0
                width: skip.triW
                height: skip.triSize
                transformOrigin: skip.direction > 0 ? Item.Left : Item.Right
                scale: idx === track.iIn ? track.p : 1
                x: track.posFor(idx)
                opacity: idx === track.iFront ? 1 - track.p : 1
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "#DFE6F2"
                    strokeColor: "#DFE6F2"
                    strokeWidth: skip.triCorner * 2
                    joinStyle: ShapePath.RoundJoin
                    capStyle: ShapePath.RoundCap
                    PathMove {
                        x: skip.direction > 0 ? skip.triCorner : skip.triW - skip.triCorner
                        y: skip.triCorner
                    }
                    PathLine {
                        x: skip.direction > 0 ? skip.triCorner : skip.triW - skip.triCorner
                        y: skip.triSize - skip.triCorner
                    }
                    PathLine {
                        x: skip.direction > 0 ? skip.triW - skip.triCorner : skip.triCorner
                        y: skip.triSize / 2
                    }
                    PathLine {
                        x: skip.direction > 0 ? skip.triCorner : skip.triW - skip.triCorner
                        y: skip.triCorner
                    }
                }
            }
            Shape {
                property int idx: 1
                width: skip.triW
                height: skip.triSize
                transformOrigin: skip.direction > 0 ? Item.Left : Item.Right
                scale: idx === track.iIn ? track.p : 1
                x: track.posFor(idx)
                opacity: idx === track.iFront ? 1 - track.p : 1
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "#DFE6F2"
                    strokeColor: "#DFE6F2"
                    strokeWidth: skip.triCorner * 2
                    joinStyle: ShapePath.RoundJoin
                    capStyle: ShapePath.RoundCap
                    PathMove {
                        x: skip.direction > 0 ? skip.triCorner : skip.triW - skip.triCorner
                        y: skip.triCorner
                    }
                    PathLine {
                        x: skip.direction > 0 ? skip.triCorner : skip.triW - skip.triCorner
                        y: skip.triSize - skip.triCorner
                    }
                    PathLine {
                        x: skip.direction > 0 ? skip.triW - skip.triCorner : skip.triCorner
                        y: skip.triSize / 2
                    }
                    PathLine {
                        x: skip.direction > 0 ? skip.triCorner : skip.triW - skip.triCorner
                        y: skip.triCorner
                    }
                }
            }
            Shape {
                property int idx: 2
                width: skip.triW
                height: skip.triSize
                transformOrigin: skip.direction > 0 ? Item.Left : Item.Right
                scale: idx === track.iIn ? track.p : 1
                x: track.posFor(idx)
                opacity: idx === track.iFront ? 1 - track.p : 1
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "#DFE6F2"
                    strokeColor: "#DFE6F2"
                    strokeWidth: skip.triCorner * 2
                    joinStyle: ShapePath.RoundJoin
                    capStyle: ShapePath.RoundCap
                    PathMove {
                        x: skip.direction > 0 ? skip.triCorner : skip.triW - skip.triCorner
                        y: skip.triCorner
                    }
                    PathLine {
                        x: skip.direction > 0 ? skip.triCorner : skip.triW - skip.triCorner
                        y: skip.triSize - skip.triCorner
                    }
                    PathLine {
                        x: skip.direction > 0 ? skip.triW - skip.triCorner : skip.triCorner
                        y: skip.triSize / 2
                    }
                    PathLine {
                        x: skip.direction > 0 ? skip.triCorner : skip.triW - skip.triCorner
                        y: skip.triCorner
                    }
                }
            }
        }

        MouseArea {
            id: skipMa
            anchors.fill: parent
            onClicked: skip.go()
        }
    }
}
