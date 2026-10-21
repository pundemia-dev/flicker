import QtQuick
import "../../components"
import "../../config"

// Lyrics panel of the player module (right of the info column). Synced
// lyrics follow the track Apple Music style: the playing line sits at
// `anchorAt` of the height, bright and full size; past lines dim more than
// the coming ones, everything moves on springs. A long gap between lines
// (and a long intro) is an empty line drawn as three dots filling with the
// gap's progress. Tap a line = seek there (TapHandler: a passive grab, so a
// swipe-up over the panel still closes the module). Wheel / touchpad scroll
// detaches the follow for `followDelayMs`. Unsynced lyrics just scroll.
// Top / bottom edges fade out per line (opacity from the line's place in
// the panel; MultiEffect masks are binary).
Item {
    id: root
    required property var lyrics
    property var player: null
    property var cfg: ({})
    property bool running: true

    readonly property real fontSize: cfg.fontSize ?? 15
    readonly property real anchorAt: 0.36
    readonly property bool canSeek: (player?.canSeek ?? false) && (player?.positionSupported ?? false)

    // Position sampled faster than the module's 1 s tick (MprisPlayer
    // position reads are live): a line switches within ~0.1 s.
    property real pos: player?.position ?? 0
    Timer {
        interval: 100
        repeat: true
        running: root.running && root.lyrics.synced && root.lyrics.current
        triggeredOnStart: true
        onTriggered: root.pos = root.player?.position ?? 0
    }

    readonly property bool showLines: lyrics.current && lyrics.status === "ok" && !lyrics.instrumental
    readonly property int cur: showLines ? lyrics.indexForTime(pos) : -1

    // Manual scroll (px added to the followed position) + its timeout.
    property real manual: 0
    property bool following: true
    Timer {
        id: followBack
        interval: root.cfg.followDelayMs ?? 3000
        onTriggered: {
            root.manual = 0;
            root.following = true;
        }
    }
    onCurChanged: {
        if (root.following)
            root.manual = 0;
    }
    Connections {
        target: root.lyrics
        function onLinesChanged(): void {
            root.manual = 0;
            root.following = true;
            followBack.stop();
        }
    }

    // ---- lines -----------------------------------------------------------

    Item {
        id: viewport
        anchors.fill: parent
        clip: true
        opacity: root.showLines ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { Spring { stiffness: 3; damp: 0.5; eps: 0.005 } }
        readonly property real fadePx: height * (root.cfg.fadeEdge ?? 0.22)

        Column {
            id: col
            width: parent.width
            spacing: root.cfg.lineSpacing ?? 9

            // Followed y: the playing line's centre at anchorAt (before the
            // first line: the first one there). Unsynced: from the top.
            // itemAt() is not reactive: `rev` re-reads it once the delegates
            // are rebuilt (a new track with the same line count keeps `count`).
            property int rev: 0
            readonly property Item curItem: rev, rep.count > 0 ? rep.itemAt(Math.max(0, root.cur)) : null
            readonly property real followY: root.lyrics.synced && curItem
                ? viewport.height * root.anchorAt - curItem.y - curItem.height / 2
                : viewport.height * (root.cfg.fadeEdge ?? 0.22) * 0.6
            readonly property real minY: Math.min(followY, viewport.height * 0.5 - height)
            readonly property real maxY: Math.max(followY, viewport.height * 0.4)

            y: Math.max(minY, Math.min(maxY, followY + root.manual))
            Behavior on y { Spring { stiffness: 2.6; damp: 0.42; eps: 0.25 } }

            Repeater {
                id: rep
                model: root.lyrics.lines
                onItemAdded: col.rev += 1

                delegate: Item {
                    id: line
                    required property var modelData
                    required property int index
                    readonly property bool empty: (modelData.x ?? "") === ""
                    readonly property bool isCur: index === root.cur
                    readonly property real nextT: index + 1 < root.lyrics.lines.length ? root.lyrics.lines[index + 1].t : modelData.t
                    // A real pause (dots) vs a stanza break (small gap).
                    readonly property bool dots: empty && root.lyrics.synced
                        && nextT - modelData.t >= (root.cfg.gapDotsSec ?? 4)
                    readonly property real progress: isCur && nextT > modelData.t
                        ? Math.max(0, Math.min(1, (root.pos - root.lyrics.offset - modelData.t) / (nextT - modelData.t))) : 0
                    readonly property int dist: root.cur < 0 ? index + 1 : Math.abs(index - root.cur)

                    width: col.width
                    height: empty ? (dots ? (isCur ? 22 : 12) : root.fontSize * 0.4) : text.implicitHeight
                    Behavior on height { Spring { stiffness: 3; damp: 0.45; eps: 0.25 } }

                    // Edge fade: live (follows the column's spring), so no
                    // Behavior here; the state opacity / scale is on `body`.
                    readonly property real centerY: col.y + y + height / 2
                    opacity: viewport.fadePx > 0
                        ? Math.max(0, Math.min(1, centerY / viewport.fadePx, (viewport.height - centerY) / viewport.fadePx))
                        : 1

                    Item {
                        id: body
                        anchors.fill: parent
                        opacity: {
                            if (!root.lyrics.synced)
                                return 0.85;
                            if (line.isCur)
                                return 1;
                            if (hover.hovered && root.canSeek)
                                return 0.8;
                            const base = line.index < root.cur ? (root.cfg.pastOpacity ?? 0.4) : (root.cfg.nextOpacity ?? 0.55);
                            return Math.max(0.18, base - 0.07 * (line.dist - 1));
                        }
                        Behavior on opacity { Spring { stiffness: 3; damp: 0.5; eps: 0.005 } }

                        scale: line.isCur || !root.lyrics.synced ? 1 : (root.cfg.inactiveScale ?? 0.94)
                        transformOrigin: Item.Left
                        Behavior on scale { Spring { stiffness: 3; damp: 0.42; eps: 0.002 } }

                        Text {
                            id: text
                            visible: !line.empty
                            width: parent.width
                            text: line.modelData.x ?? ""
                            color: "#F4F7FC"
                            font.pixelSize: root.fontSize
                            font.weight: Font.Bold
                            wrapMode: Text.WordWrap
                            lineHeight: 1.08
                        }

                        // Gap dots: each lights up over its third of the pause.
                        Row {
                            visible: line.dots
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Repeater {
                                model: 3
                                Rectangle {
                                    required property int index
                                    readonly property real fill: Math.max(0, Math.min(1, line.progress * 3 - index))
                                    width: line.isCur ? 9 : 6
                                    height: width
                                    radius: width / 2
                                    color: "#F4F7FC"
                                    opacity: line.isCur ? 0.3 + 0.7 * fill : 1
                                    Behavior on width { Spring { stiffness: 3; damp: 0.4; eps: 0.1 } }
                                }
                            }
                        }
                    }

                    HoverHandler {
                        id: hover
                        enabled: root.lyrics.synced && root.canSeek
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        enabled: root.lyrics.synced && root.canSeek
                        onTapped: {
                            const t = root.lyrics.timeForIndex(line.index);
                            if (t >= 0 && root.player) {
                                root.player.position = t;
                                root.pos = t;
                                root.manual = 0;
                                root.following = true;
                                followBack.stop();
                            }
                        }
                    }
                }
            }
        }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const d = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 120 * 40;
                const lo = col.minY - col.followY;
                const hi = col.maxY - col.followY;
                root.manual = Math.max(lo, Math.min(hi, root.manual + d));
                root.following = false;
                if (root.lyrics.synced)
                    followBack.restart();
            }
        }
    }

    // ---- states (searching / none / instrumental / error) ----------------

    Column {
        id: placeholder
        anchors.centerIn: parent
        width: parent.width
        spacing: 6
        readonly property string mode: {
            const l = root.lyrics;
            if (l.status === "loading" || (l.status === "ok" && !l.current))
                return "loading";
            if (l.status === "error")
                return "error";
            if (l.status === "ok" && l.instrumental && l.current)
                return "instrumental";
            if (l.status === "none" || l.status === "idle")
                return "none";
            return "";
        }
        opacity: mode !== "" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { Spring { stiffness: 3; damp: 0.5; eps: 0.005 } }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "♪"
            color: "#B3EBEBF5"
            font.pixelSize: 26
            opacity: placeholder.mode === "loading" ? 0.35 + 0.65 * pulse.value : 1

            // Searching: a slow breathe on the note (spring ping-pong).
            QtObject {
                id: pulse
                property real value: 0
                property bool up: true
                Behavior on value { Spring { stiffness: 1.2; damp: 0.6; eps: 0.02 } }
            }
            Timer {
                interval: 700
                repeat: true
                running: placeholder.mode === "loading" && root.running
                triggeredOnStart: true
                onTriggered: {
                    pulse.up = !pulse.up;
                    pulse.value = pulse.up ? 1 : 0;
                }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: placeholder.mode === "loading" ? I18n.tr("Searching for lyrics…")
                : placeholder.mode === "error" ? I18n.tr("Couldn't load lyrics")
                : placeholder.mode === "instrumental" ? I18n.tr("Instrumental")
                : I18n.tr("No lyrics found")
            color: "#B3EBEBF5"
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: placeholder.mode === "error"
            text: I18n.tr("Tap to retry")
            color: "#80EBEBF5"
            font.pixelSize: 12
            TapHandler {
                onTapped: root.lyrics.retry()
            }
        }
    }
}
