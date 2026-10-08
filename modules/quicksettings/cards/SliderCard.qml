import QtQuick
import QtQuick.Shapes
import "../../../components"
import "../../../config"
import "../../../components/Knockout.js" as Knockout

// Fill slider (volume, brightness) in the OSD look (modules/osd): the card
// itself is the capsule — a light fill grows from the bottom (small/tall/
// large) or the left (wide/panorama), split from the track by a gap with
// rounded inner edges (gap/innerRadius/springs shared with Config.osd). The
// glyph (and title) is drawn twice: light over the track, dark ink clipped
// to the fill, so it stays legible wherever the fill edge crosses it. No
// percent. `volume: true` swaps the glyph for the shape-built VolumeIcon
// (arcs by level, slash on mute, pulse at 0, wave at 100%) and tints the
// fill orange past 100%. Drags are RELATIVE (iOS): the value moves by the
// pointer delta, a press never jumps it. Tap = `activate()` (mute), long
// press = edit mode, wheel = ±cfg.wheelStep. Layout per form:
//   small     glyph centred
//   tall      glyph at the bottom
//   wide      glyph left
//   large /   glyph + title top-left
//   panorama
Item {
    id: root
    property var card: null
    property var haptics: null
    property string glyph: ""
    property string title: ""
    // Normalised 0..1.
    property real value: 0
    property var activate: null
    // VolumeIcon instead of the glyph; level = shown * levelScale (real
    // volume: the bar spans 0..maxVolume).
    property bool volume: false
    property bool muted: false
    property real levelScale: 1
    // Glyph tint for both ink copies; transparent = light/dark ink.
    property color iconColor: "transparent"
    signal moved(real value)

    // QsCard skips its own background: the gap must show the island.
    readonly property bool ownSurface: true

    readonly property var theme: root.card?.theme ?? null
    readonly property var cfg: root.card?.cfg ?? null
    readonly property var osd: Config.data.osd
    readonly property string form: root.card?.form ?? "small"
    readonly property bool horizontal: root.form === "wide" || root.form === "panorama"
    readonly property real pad: (root.cfg?.padding) ?? 12
    readonly property real unit: (root.cfg?.unit) ?? 80

    // Local value while dragging (the service applies volume async).
    property real dragValue: 0
    readonly property real shown: area.dragging ? root.dragValue : Math.max(0, Math.min(1, root.value))
    property real fill: root.shown
    Behavior on fill {
        enabled: !area.dragging
        Spring { stiffness: root.osd.fillStiffness; damp: root.osd.fillDamping; eps: 0.001 }
    }

    readonly property real level: root.shown * root.levelScale
    readonly property bool boosted: root.volume && !root.muted && root.level > 1.001
    readonly property int arcs: root.level <= 0.001 ? 0 : root.level < 1 / 3 ? 1 : root.level < 2 / 3 ? 2 : 3
    readonly property color lightInk: root.muted ? (root.theme?.subtleFg ?? "#B9C0CB") : "white"
    readonly property color darkInk: root.theme?.qsOnFill ?? "#1C1C1E"

    function set(v: real): void {
        const was = root.shown;
        root.dragValue = Math.max(0, Math.min(1, v));
        // Hit an end (Config.haptics.limits): once per arrival.
        if ((root.dragValue <= 0 || root.dragValue >= 1) && root.dragValue !== was
                && Config.data.haptics?.limits)
            root.haptics?.release();
        root.moved(root.dragValue);
    }

    // VolumeIcon accents on the real level (both ink copies listen).
    signal volumePulse
    signal volumeWave
    property real lastLevel: -1
    onLevelChanged: {
        if (root.volume && root.lastLevel >= 0) {
            if (root.level <= 0.001 && root.lastLevel > 0.001)
                root.volumePulse();
            else if (root.level >= 0.999 && root.lastLevel < 0.999)
                root.volumeWave();
        } else if (!root.volume && root.lastLevel >= 0 && root.level >= 0.999 && root.lastLevel < 0.999) {
            // Plain glyph (brightness): VolumeIcon-style pulse at 100%.
            glyphBump.bump();
        }
        root.lastLevel = root.level;
    }

    GlyphBump {
        id: glyphBump
    }

    // Glyph change pops in from a smaller scale (OSD).
    property real iconScale: 1
    property bool settled: false
    Component.onCompleted: root.settled = true
    onGlyphChanged: if (root.settled && !root.volume) iconPop.restart()
    Spring {
        id: iconPop
        target: root
        property: "iconScale"
        from: root.osd.iconPopFrom
        to: 1
        stiffness: root.osd.fillStiffness
        damp: root.osd.fillDamping
        eps: 0.002
    }

    RoundedClip {
        id: bar
        anchors.fill: parent
        radius: root.card?.radius ?? 36

        readonly property real span: root.horizontal ? bar.width : bar.height
        readonly property real fillLen: bar.span * root.fill
        // Fades out near the ends so 0% / 100% stay one solid piece.
        readonly property real gapLen: root.osd.gap
            * Math.max(0, Math.min(1, fillLen / root.osd.gap, (bar.span - fillLen) / root.osd.gap))
        readonly property real innerR: root.osd.innerRadius

        // Frost: the card is knocked out of the island tint as a whole, so
        // the gap between fill and track repaints the tint itself — the
        // exact complement (bar − track − fill, even-odd, capsule-clipped).
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            opacity: root.card?.frost?.progress ?? 0
            ShapePath {
                fillColor: root.theme?.frostBody ?? "transparent"
                strokeWidth: -1
                fillRule: ShapePath.OddEvenFill
                PathSvg {
                    path: {
                        if ((root.card?.frost?.progress ?? 0) < 0.001)
                            return "";
                        const W = bar.width, H = bar.height;
                        const f = bar.fillLen, t = Math.max(0, bar.span - bar.fillLen - bar.gapLen);
                        const fi = Math.min(bar.innerR, f / 2), ti = Math.min(bar.innerR, t / 2);
                        const parts = [Knockout.hole(0, 0, W, H, 0)];
                        if (t >= 0.5)
                            parts.push(root.horizontal ? Knockout.hole(W - t, 0, t, H, ti) : Knockout.hole(0, 0, W, t, ti));
                        if (f >= 0.5)
                            parts.push(root.horizontal ? Knockout.hole(0, 0, f, H, fi) : Knockout.hole(0, H - f, W, f, fi));
                        return Knockout.holesPath(parts);
                    }
                }
            }
        }

        Rectangle {
            // Track: the rest of the span past fill + gap.
            readonly property real len: Math.max(0, bar.span - bar.fillLen - bar.gapLen)
            width: root.horizontal ? len : bar.width
            height: root.horizontal ? bar.height : len
            x: root.horizontal ? bar.width - len : 0
            radius: Math.min(bar.innerR, len / 2)
            color: root.card?.frost?.surface(root.theme?.qsCardBg ?? "#000000") ?? (root.theme?.qsCardBg ?? "#000000")
        }
        Ink {
            inkColor: root.lightInk
        }
        Item {
            id: fillClip
            width: root.horizontal ? Math.max(0, bar.fillLen) : bar.width
            height: root.horizontal ? bar.height : Math.max(0, bar.fillLen)
            y: root.horizontal ? 0 : bar.height - height
            clip: true

            Rectangle {
                anchors.fill: parent
                radius: Math.min(bar.innerR, (root.horizontal ? width : height) / 2)
                color: root.boosted ? (root.theme?.accentOrange ?? "#E58B4D") : (root.theme?.qsFill ?? "#F2F2F7")
            }
            Ink {
                y: -fillClip.y
                inkColor: root.darkInk
            }
        }
    }

    // Glyph slot: centre (small), bottom (tall), left (wide), top-left (large).
    readonly property real iconSize: ((root.cfg?.iconSize) ?? 22) * ((root.cfg?.sliderIconScale) ?? 1.5)
    readonly property point glyphCenter: {
        const half = root.unit / 2;
        if (root.form === "small")
            return Qt.point(root.width / 2, root.height / 2);
        if (root.form === "tall")
            return Qt.point(root.width / 2, root.height - half);
        if (root.horizontal && root.card?.spanH === 1)
            return Qt.point(half, root.height / 2);
        return Qt.point(root.pad + root.iconSize / 2, root.pad + root.iconSize / 2);
    }

    // Glyph + title in card coordinates (each copy is placed so it lines up
    // with the card).
    component Ink: Item {
        id: ink
        property color inkColor
        readonly property color glyphColor: root.iconColor.a > 0 ? root.iconColor : ink.inkColor
        width: root.width
        height: root.height


        Item {
            // opacity, NOT visible: CurveRenderer Shapes never repaint after
            // a visible toggle (AGENTS.md).
            opacity: root.volume ? 1 : 0
            width: volIcon.implicitWidth
            height: root.iconSize
            x: root.glyphCenter.x - width / 2
            y: root.glyphCenter.y - height / 2

            VolumeIcon {
                id: volIcon
                anchors.centerIn: parent
                size: root.iconSize
                color: ink.glyphColor
                arcs: root.arcs
                muted: root.muted
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
        Icon {
            opacity: root.volume ? 0 : 1
            x: root.glyphCenter.x - width / 2
            y: root.glyphCenter.y - height / 2
            text: root.glyph
            scale: root.iconScale * glyphBump.value
            font.family: root.theme?.iconFamily ?? "tabler-icons"
            iconSize: root.iconSize
            iconColor: ink.glyphColor
        }
        Text {
            visible: root.form === "large" || root.form === "panorama"
            x: root.pad + root.iconSize + 8
            y: root.glyphCenter.y - height / 2
            width: root.width - x - root.pad
            text: root.title
            font.pixelSize: (root.cfg?.titleSize) ?? 13
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: ink.inkColor
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        pressAndHoldInterval: (root.cfg?.holdMs) ?? 450
        property point start
        property real startValue: 0
        property bool dragging: false
        property bool held: false

        onPressed: mouse => {
            start = Qt.point(mouse.x, mouse.y);
            startValue = root.shown;
            dragging = false;
            held = false;
        }
        onPressAndHold: {
            if (dragging)
                return;
            held = true;
            root.card?.holdRequested();
        }
        onPositionChanged: mouse => {
            if (held)
                return;
            const d = root.horizontal ? (mouse.x - start.x) / root.width : (start.y - mouse.y) / root.height;
            if (!dragging && Math.abs(d) * (root.horizontal ? root.width : root.height) > 3) {
                root.dragValue = startValue;
                dragging = true;
            }
            if (dragging)
                root.set(startValue + d);
        }
        onReleased: {
            if (!dragging && !held && typeof root.activate === "function")
                root.activate();
            dragging = false;
        }
        onCanceled: dragging = false
        onWheel: wheel => {
            const step = (root.cfg?.wheelStep) ?? 0.05;
            root.set(root.shown + (wheel.angleDelta.y > 0 ? step : -step));
        }
    }
}
