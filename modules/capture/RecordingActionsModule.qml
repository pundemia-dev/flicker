import QtQuick
import "../../components"
import "../../config"

// Recording controls in the island (red clock plate click; port of pShell
// RecordPill's recording row): pulsing dot + elapsed time, the speed drum
// (SpeedRuler → recorder.speed), then discard / audio source (cycles none →
// system → mic → both, switched live) / pause / stop. Stop and discard close
// the module (the plate leaves with it). Proportions copied from the user's
// iOS reference shot (island 815×182 → scaled to the island height); all
// gaps in `recorder.controls`, laid out left to right with explicit x.
Item {
    id: root
    required property var recorder
    required property var theme
    required property var cfg
    property var haptics: null
    signal closeRequested

    // Stopped elsewhere (IPC / plate): nothing left to control.
    Connections {
        target: root.recorder
        function onRecordingChanged(): void {
            if (!root.recorder.recording)
                root.closeRequested();
        }
    }

    // h:mm:ss (the bar plate keeps the short mm:ss of elapsedText).
    readonly property string elapsedHms: {
        const t = root.recorder.elapsedSeconds ?? 0;
        const p = n => n.toString().padStart(2, "0");
        return `${p(Math.floor(t / 3600))}:${p(Math.floor(t / 60) % 60)}:${p(t % 60)}`;
    }

    readonly property var c: root.recorder.cfg?.controls ?? ({})
    readonly property var islandSize: Config.data.modules?.["recording-actions"] ?? ({})
    // Config height, not the animated one — the island width follows this.
    readonly property real islandH: root.islandSize.height ?? 96
    readonly property real cy: root.height / 2
    readonly property real buttonSize: root.c.buttonSize ?? 55
    // Right gap = the buttons' top/bottom gap.
    readonly property real edgeGap: (root.islandH - root.buttonSize) / 2
    readonly property real dotSize: root.c.dotSize ?? 15

    // Left to right (each x = previous right edge + its gap).
    readonly property real dotX: (root.c.dotCenter ?? 44) - root.dotSize / 2
    readonly property real timeX: root.dotX + root.dotSize + (root.c.dotGap ?? 5)
    readonly property real rulerX: root.timeX + timeText.implicitWidth + (root.c.rulerGap ?? 27)
    readonly property real buttonSpacing: root.c.buttonSpacing ?? 9
    // At rest only pause + stop show and the ruler sits in the middle of the
    // island (same gap to the left and the right edge, reference look);
    // hovering the buttons widens the island and discard + audio slide out
    // left of pause. `buttonsGap` = the minimum ruler → pause gap.
    readonly property real restButtons: 2 * root.buttonSize + root.buttonSpacing + root.edgeGap
    readonly property real restWidth: Math.round(root.rulerX + ruler.implicitWidth
        + Math.max(root.rulerX, (root.c.buttonsGap ?? 18) + root.restButtons))
    readonly property real extraWidth: 2 * (root.buttonSize + root.buttonSpacing)
    property bool expanded: false
    readonly property real preferredWidth: root.restWidth + (root.expanded ? root.extraWidth : 0)
    // Quicker, nearly critically damped island spring for the button reveal
    // (only once open and while it is in play: the open / close morph keeps
    // the island's default).
    readonly property var widthSpring: root.settled && (root.expanded || root.reveal > 0)
        ? ({ stiffness: root.c.revealStiffness ?? 9, damping: root.c.revealDamping ?? 0.75 }) : null
    // 0..1 = how far the (springing) island has opened for the extra buttons.
    readonly property real reveal: Math.max(0, Math.min(1, (root.width - root.restWidth) / root.extraWidth))

    // Hover over the button group (incl. half the gap before it) opens it;
    // it closes hoverHoldMs after the pointer left. The handler sits on the
    // root: an ancestor still sees hover while a button's MouseArea has it.
    HoverHandler {
        id: hover
    }
    // Pointer inputs of the zone logic (overridable: a test harness drives
    // them without a real pointer).
    property bool pointerIn: hover.hovered
    property real pointerSceneX: hover.point.scenePosition.x
    property real pointerSceneY: hover.point.scenePosition.y
    // Zone measured from the RIGHT edge (the centred island grows both ways,
    // the pointer's x in module coords shifts as it opens) and by the live
    // reveal, not `expanded` (that would feed back into itself).
    readonly property real zoneDepth: root.restButtons + root.reveal * root.extraWidth
        + (root.c.buttonsGap ?? 18) / 2
    // Pointer x in module coords from its WINDOW position: point.position is
    // only refreshed on pointer motion, so it goes stale while the island
    // grows under a still pointer (the island window is full-width, scene
    // coords stay valid). `root.width` re-maps as the centred island moves.
    readonly property real pointerX: {
        root.width;
        return root.mapFromItem(null, root.pointerSceneX, 0).x;
    }
    // The mapped x lags the springing island by a frame: `zoneSlack` of
    // hysteresis while open keeps the zone from flapping as it grows.
    readonly property bool overZone: root.pointerIn
        && root.width - root.pointerX <= root.zoneDepth + (root.expanded ? (root.c.zoneSlack ?? 12) : 0)
    // No auto-open on opening: while the island grows out of the bar the
    // narrow module is all "zone", and the pointer may already sit where the
    // buttons land. Armed (once the island reached its rest width) only on
    // positive evidence: the pointer rests on the island OFF the zone for
    // armDelayMs, leaves the island, or enters it across an edge
    // (`entryEdge`). A still pointer the island merely grew under appears
    // deep inside and never arms it until it leaves the zone.
    property bool settled: false
    property bool armed: false
    onWidthChanged: if (!root.settled && root.width >= root.restWidth - 1)
        root.settled = true
    Component.onCompleted: if (root.width >= root.restWidth - 1)
        root.settled = true
    readonly property bool canArm: root.settled && root.pointerIn && !root.overZone
    onCanArmChanged: root.canArm ? armTimer.restart() : armTimer.stop()
    Timer {
        id: armTimer
        interval: root.c.armDelayMs ?? 200
        onTriggered: root.armed = true
    }
    // Entry check: the hover-enter can carry a stale position (seen: scene
    // 0,0 → outside the module), so a point outside the module is ignored
    // and the next one decides; the first point inside settles it.
    property bool entryPending: false
    onPointerInChanged: {
        if (!root.settled || root.armed)
            return;
        if (!root.pointerIn) {
            root.armed = true;
            return;
        }
        root.entryPending = true;
        root.checkEntry();
    }
    onPointerSceneXChanged: root.checkEntry()
    onPointerSceneYChanged: root.checkEntry()
    function checkEntry(): void {
        if (!root.entryPending || !root.pointerIn)
            return;
        const p = root.mapFromItem(null, root.pointerSceneX, root.pointerSceneY);
        if (p.x < 0 || p.y < 0 || p.x > root.width || p.y > root.height)
            return;
        root.entryPending = false;
        const e = root.c.entryEdge ?? 12;
        if (p.x < e || p.y < e || p.x > root.width - e || p.y > root.height - e)
            root.armed = true;
    }
    readonly property bool inZone: root.armed && root.overZone
    // Deferred: setting `expanded` inside the change chain of `overZone`
    // (which reads it for the slack) is a binding loop.
    onInZoneChanged: Qt.callLater(root.applyZone)
    function applyZone(): void {
        if (root.inZone) {
            closeTimer.stop();
            root.expanded = true;
        } else if (root.expanded) {
            closeTimer.restart();
        }
    }
    Timer {
        id: closeTimer
        interval: root.c.hoverHoldMs ?? 300
        onTriggered: root.expanded = false
    }

    readonly property var audioGlyphs: ({ none: "\uf1c3", system: "\ueb51", mic: "\ueaf0", both: "\ueb90" })

    property font timeFont: Qt.font({ family: root.theme.fontFamily, pixelSize: root.c.timeSize ?? 16, letterSpacing: root.c.timeLetterSpacing ?? 0, weight: Font.DemiBold, features: { "tnum": 1 } })
    TextMetrics {
        id: digits
        font: root.timeFont
        text: "0123456789"
    }

    Rectangle {
        x: root.dotX
        y: root.cy - height / 2
        width: root.dotSize
        height: width
        radius: width / 2
        color: root.recorder.paused ? root.theme.subtleFg : root.theme.recDot

        SequentialAnimation on opacity {
            running: root.recorder.recording && !root.recorder.paused
            loops: Animation.Infinite
            NumberAnimation { to: 0.25; duration: root.cfg.fadeInMs * 3 }
            NumberAnimation { to: 1; duration: root.cfg.fadeInMs * 3 }
        }
    }

    Text {
        id: timeText
        x: root.timeX
        // Digit ink centred on the island (not the line box).
        y: root.cy - timeText.baselineOffset + digits.tightBoundingRect.height / 2
        text: root.elapsedHms
        color: root.theme.islandFg
        font: root.timeFont
    }

    SpeedRuler {
        id: ruler
        x: root.rulerX
        height: root.height
        recorder: root.recorder
        cfg: root.recorder.cfg
        theme: root.theme
        haptics: root.haptics
    }

    Repeater {
        model: [
            { kind: "discard", glyph: "\ueb41", fg: root.theme.recButtonInk, bg: root.theme.recButtonBg, run: () => { root.recorder.discard(); root.closeRequested(); } },
            { kind: "audio", glyph: root.audioGlyphs[root.recorder.audio] ?? "\uf1c3", fg: root.theme.recButtonInk, bg: root.theme.recButtonBg, run: () => root.recorder.cycleAudio() },
            { kind: "pause", glyph: root.recorder.paused ? "\uf691" : "", fg: root.theme.recButtonInk, bg: root.theme.recButtonBg, run: () => root.recorder.togglePause() },
            { kind: "stop", glyph: "", fg: root.theme.recStopInk, bg: root.theme.recStopBg, run: () => { root.recorder.stop(); root.closeRequested(); } }
        ]

        IconButton {
            id: btn
            required property var modelData
            required property int index
            // Anchored to the island's right edge (its live, springing width),
            // index 3 = stop at the edge; discard / audio fade + scale in as
            // the island opens.
            readonly property bool extra: btn.index < 2
            x: root.width - root.edgeGap - (4 - btn.index) * root.buttonSize - (3 - btn.index) * root.buttonSpacing
            y: root.cy - height / 2
            // Smoothstep over the last part of the reveal: they appear once
            // there is room beside the ruler and leave before it closes in.
            readonly property real appear: {
                const a = root.c.revealFadeFrom ?? 0.35;
                const t = Math.max(0, Math.min(1, (root.reveal - a) / (1 - a)));
                return t * t * (3 - 2 * t);
            }
            opacity: btn.extra ? btn.appear : 1
            // A transform, so IconButton's own press pop (scale) still works.
            transform: Scale {
                origin.x: btn.width / 2
                origin.y: btn.height / 2
                xScale: btn.extra ? 0.8 + 0.2 * btn.appear : 1
                yScale: xScale
            }
            enabled: !btn.extra || root.reveal > 0.5
            visible: opacity > 0.01
            theme: root.theme
            glow: false
            inkCentred: true
            width: root.buttonSize
            height: width
            glyph: btn.modelData.glyph
            fg: btn.modelData.fg
            bg: btn.modelData.bg
            hoverBg: Qt.lighter(btn.modelData.bg, 1.3)
            iconSize: root.c.iconSize ?? 22
            onClicked: btn.modelData.run()

            // Drawn glyphs (reference): two rounded pause bars, a stop square.
            Row {
                visible: btn.modelData.kind === "pause" && !root.recorder.paused
                anchors.centerIn: parent
                spacing: root.c.pauseGap ?? 5.3
                Repeater {
                    model: 2
                    Rectangle {
                        width: root.c.pauseBarWidth ?? 6.3
                        height: root.c.pauseBarHeight ?? 18
                        radius: root.c.pauseBarRadius ?? 2
                        color: btn.modelData.fg
                    }
                }
            }
            Rectangle {
                visible: btn.modelData.kind === "stop"
                anchors.centerIn: parent
                width: root.c.stopSize ?? 18.5
                height: width
                radius: root.c.stopRadius ?? 4
                color: btn.modelData.fg
            }
        }
    }
}
