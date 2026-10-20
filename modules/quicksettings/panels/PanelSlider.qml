import QtQuick
import "../../../components"

// Slim volume slider of the QS list panels (audio panel rows): a capsule,
// light fill from the left, the glyph inside on the left drawn twice (light
// over the track, dark ink clipped to the fill). Tap on the glyph = mute
// toggle (`muteToggled`; the glyph swaps to `mutedGlyph`, the fill drops to
// 0); press elsewhere sets the value where it lands, drag follows, wheel =
// ±wheelStep. Local value while dragging (PipeWire applies volume async).
// `level` >= 0 adds a live meter under the capsule (microphone input).
Item {
    id: root
    property var pc: ({})
    property var theme: null
    property var frost: null
    property real value: 0
    property bool muted: false
    property string glyph: ""
    property string mutedGlyph: ""
    property real level: -1
    property real wheelStep: 0.05
    property color fillColor: "#F0F4FB"
    signal moved(real value)
    signal muteToggled

    readonly property real barH: root.pc.sliderHeight ?? 28
    readonly property bool metered: root.level >= 0
    height: root.barH + (root.metered ? 7 : 0)

    property real dragValue: 0
    readonly property real shown: ma.dragging ? root.dragValue : (root.muted ? 0 : Math.max(0, Math.min(1, root.value)))
    property real fill: root.shown
    Behavior on fill {
        enabled: !ma.dragging
        Spring { stiffness: 6; damp: 0.6; eps: 0.001 }
    }

    Rectangle {
        id: track
        width: parent.width
        height: root.barH
        radius: height / 2
        color: root.frost?.layerColor(root.theme?.qsDisc ?? "#3A3A3C") ?? (root.theme?.qsDisc ?? "#3A3A3C")
        clip: true

        Icon {
            id: lightInk
            x: 0
            width: track.height + 4
            height: track.height
            text: root.muted ? root.mutedGlyph : root.glyph
            font.family: root.theme?.iconFamily ?? "tabler-icons"
            iconSize: (root.pc.glyphSize ?? 20) - 4
            iconColor: root.muted ? (root.theme?.cardDim ?? "#99EBEBF5") : "white"
        }
        Item {
            id: fillBox
            width: Math.max(track.height, track.height + (track.width - track.height) * root.fill)
            height: track.height
            clip: true
            opacity: root.fill > 0.001 ? 1 : 0
            Rectangle {
                width: fillBox.width
                height: track.height
                radius: track.radius
                color: root.fillColor
            }
            Icon {
                width: lightInk.width
                height: lightInk.height
                text: lightInk.text
                font.family: lightInk.font.family
                iconSize: lightInk.iconSize
                iconColor: "#1C1C1E"
            }
        }
    }

    // Live input level under the capsule (sqrt: speech sits low linearly).
    Item {
        visible: root.metered
        y: root.barH + 4
        x: track.radius
        width: track.width - 2 * track.radius
        height: 3
        Rectangle {
            anchors.fill: parent
            radius: 1.5
            color: "#1FFFFFFF"
        }
        Rectangle {
            property real lv: Math.sqrt(Math.max(0, Math.min(1, root.level)))
            Behavior on lv { Spring { stiffness: 14; damp: 0.9; eps: 0.002 } }
            width: parent.width * lv
            height: parent.height
            radius: 1.5
            color: root.theme?.qsGreen ?? "#30D158"
            opacity: root.muted ? 0.3 : 1
        }
    }

    MouseArea {
        id: ma
        width: parent.width
        height: root.barH
        cursorShape: Qt.PointingHandCursor
        property bool dragging: false
        property bool onGlyph: false
        function setAt(mx: real): void {
            root.dragValue = Math.max(0, Math.min(1, (mx - track.height / 2) / Math.max(1, width - track.height)));
            root.moved(root.dragValue);
        }
        onPressed: mouse => {
            onGlyph = mouse.x < track.height + 4;
            if (onGlyph)
                return;
            dragging = true;
            setAt(mouse.x);
        }
        onPositionChanged: mouse => {
            if (!onGlyph)
                setAt(mouse.x);
        }
        onReleased: mouse => {
            if (onGlyph && mouse.x < track.height + 4)
                root.muteToggled();
            dragging = false;
            onGlyph = false;
        }
        onCanceled: {
            dragging = false;
            onGlyph = false;
        }
        onWheel: wheel => {
            const v = Math.max(0, Math.min(1, root.shown + (wheel.angleDelta.y > 0 ? 1 : -1) * root.wheelStep));
            root.moved(v);
        }
    }
}
