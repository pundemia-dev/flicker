import QtQuick
import "../../components"
import "../../config"

// Vertical speed drum of the recording controls: grey ruler ticks on the
// left, the mirrored ruler on the right, the speed values (1x 1.5x 2x …)
// in the middle; the ticks at those values are red and a bit wider. The
// value at the vertical centre is the chosen one (`recorder.speed`).
// Motion = the timer ruler's: `pos` (index into cfg.speeds) springs to
// `selected`; wheel = one value per notch, drag follows the pointer and
// snaps on release, a tap jumps to the value under it. Ticks fade out
// toward the top / bottom (opacity per tick, no masks).
Item {
    id: root
    required property var recorder
    required property var cfg
    property var theme: null
    property var haptics: null

    readonly property var rc: root.cfg.ruler ?? ({})
    readonly property var speeds: root.cfg.speeds ?? [0.25, 0.5, 0.75, 1, 1.5, 2, 2.5, 3, 4]
    readonly property int last: Math.max(0, root.speeds.length - 1)
    readonly property int minor: root.rc.minorTicks ?? 4
    readonly property real spacing: root.rc.tickSpacing ?? 6
    // Distance between two speed values.
    readonly property real majorSpacing: root.spacing * (root.minor + 1)

    function indexOf(v: real): int {
        let best = 0;
        for (let i = 1; i < root.speeds.length; ++i)
            if (Math.abs(root.speeds[i] - v) < Math.abs(root.speeds[best] - v))
                best = i;
        return best;
    }

    property int selected: root.indexOf(root.recorder.speed)
    onSelectedChanged: root.recorder.speed = root.speeds[root.selected] ?? 1
    property real pos: root.selected
    property bool dragging: false
    Behavior on pos {
        enabled: !root.dragging
        Spring {
            stiffness: root.rc.stiffness ?? 5
            damp: root.rc.damping ?? 0.5
            eps: 0.002
        }
    }
    // Haptic detent per value passing the centre (Config.haptics.recordSpeed),
    // only while the user moves it (a wheel step / drag within the last
    // second) — the module's creation also sets `pos`.
    readonly property int centreIndex: Math.max(0, Math.min(root.last, Math.round(root.pos)))
    property real lastStepAt: 0
    onCentreIndexChanged: if ((Config.data.haptics?.recordSpeed ?? true)
            && (root.dragging || Date.now() - root.lastStepAt < 1000))
        root.haptics?.click()

    function select(i: int): void {
        root.lastStepAt = Date.now();
        root.selected = Math.max(0, Math.min(root.last, i));
        root.pos = root.selected;
    }

    readonly property real cy: root.height / 2
    // Fade by distance in ticks: full up to fadeStart, gone at fadeEnd.
    function fade(d: real): real {
        const t = Math.abs(d) * (root.minor + 1);
        const a = root.rc.fadeStart ?? 1, b = root.rc.fadeEnd ?? 4.6;
        return Math.max(0, Math.min(1, 1 - (t - a) / Math.max(0.01, b - a)));
    }
    function label(v: real): string {
        return `${Number(v.toFixed(2))}×`;
    }

    readonly property color tickColor: root.theme?.speedRulerTick ?? "#A7A7A7"
    readonly property color markColor: root.theme?.speedRulerMark ?? "#903E42"

    implicitWidth: root.rc.width ?? 112
    property font labelFont: Qt.font({ family: root.theme?.fontFamily ?? "SF Pro Display", pixelSize: root.rc.labelSize ?? 16, weight: Font.DemiBold, features: { "tnum": 1 } })
    TextMetrics {
        id: digitInk
        font: root.labelFont
        text: "0123456789"
    }

    Repeater {
        model: root.last * (root.minor + 1) + 1
        delegate: Item {
            id: tick
            required property int index
            readonly property bool major: tick.index % (root.minor + 1) === 0
            readonly property real d: tick.index / (root.minor + 1) - root.pos
            readonly property real o: root.fade(tick.d)
            visible: tick.o > 0.01
            y: root.cy + tick.d * root.majorSpacing
            width: root.width
            height: 0
            opacity: tick.o

            readonly property real len: tick.major ? (root.rc.majorLength ?? 12) : (root.rc.minorLength ?? 7)
            readonly property real thick: tick.major ? (root.rc.majorWidth ?? 2.5) : (root.rc.minorWidth ?? 1.5)
            readonly property color ink: tick.major ? root.markColor : root.tickColor

            // Left ruler (from the left edge) and its mirror (from the right).
            Repeater {
                model: 2
                Rectangle {
                    required property int index
                    x: index === 0 ? 0 : root.width - width
                    y: -height / 2
                    width: tick.len
                    height: tick.thick
                    radius: height / 2
                    color: tick.ink
                }
            }

            Text {
                id: lbl
                visible: tick.major
                anchors.horizontalCenter: parent.horizontalCenter
                // Digit ink centred on the tick (not the line box).
                y: -lbl.baselineOffset + digitInk.tightBoundingRect.height / 2
                text: root.label(root.speeds[tick.index / (root.minor + 1)] ?? 1)
                color: root.theme?.islandFg ?? "white"
                font: root.labelFont
            }
        }
    }

    // Small control (press-grab allowed): wheel steps, drag follows the
    // pointer (up = faster), a tap without a drag jumps to the tapped value.
    MouseArea {
        anchors.fill: parent
        preventStealing: true
        property real pressY: 0
        property real pressPos: 0
        property bool moved: false
        onPressed: mouse => {
            pressY = mouse.y;
            pressPos = root.pos;
            moved = false;
        }
        onPositionChanged: mouse => {
            if (!moved && Math.abs(mouse.y - pressY) < (root.rc.dragThreshold ?? 6))
                return;
            moved = true;
            root.dragging = true;
            root.pos = Math.max(0, Math.min(root.last, pressPos + (pressY - mouse.y) / root.majorSpacing));
        }
        onReleased: mouse => {
            root.dragging = false;
            if (moved)
                root.select(Math.round(root.pos));
            else
                root.select(Math.round(root.pos + (mouse.y - root.cy) / root.majorSpacing));
        }
        onCanceled: {
            root.dragging = false;
            root.select(Math.round(root.pos));
        }
        property real wheelAcc: 0
        onWheel: wheel => {
            const delta = wheel.angleDelta.y;
            if (delta === 0)
                return;
            if (wheelAcc !== 0 && Math.sign(delta) !== Math.sign(wheelAcc))
                wheelAcc = 0;
            wheelAcc += delta;
            while (Math.abs(wheelAcc) >= 120) {
                const up = wheelAcc > 0;
                wheelAcc += up ? -120 : 120;
                root.select(root.selected + (up ? -1 : 1));
            }
        }
    }
}
