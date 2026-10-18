import QtQuick
import "../../../components"
import "../../../components/MorphShape.js" as MorphShape

// Header of an expanded QS card panel: the card's glyph on a disc (accent
// while on; tap = the card's toggle), title + status line, optional
// `trailing` items on the right (PanelButton), hairline below. A status
// change blurs + fades the old line out and the new one in (springs).
// `shape` (a MorphShape kind, VPN: cookie9) draws the disc as that shape
// (MorphDot — M3Shapes is not used, see AGENTS.md): `spinning` turns it
// slowly, `busy` leaps through random shapes (morph + quarter turn + bump)
// every 800 ms and morphs back once it ends.
Item {
    id: root
    property var pc: ({})
    property var theme: null
    property var frost: null
    property real pad: 18
    property bool on: false
    property color accent: root.theme?.qsBlue ?? "#017EFC"
    property string glyph: ""
    property string title: ""
    property string status: ""
    property string shape: ""
    property bool busy: false
    property bool spinning: false
    property alias trailing: trail.data
    signal toggled

    height: (root.pc.headerHeight ?? 54) + 1

    Rectangle {
        id: disc
        readonly property real d: Math.round((root.height - 1) * 0.67)
        x: root.pad
        y: Math.round((root.height - 1 - height) / 2)
        width: d
        height: d
        radius: d / 2
        color: root.shape === "" ? discColor.value : "transparent"
        scale: discMa.pressed ? 0.9 : 1
        Behavior on scale { Spring { stiffness: 6; damp: 0.45; eps: 0.002 } }
        SpringColor {
            id: discColor
            target: root.on ? root.accent : (root.frost?.layerColor(root.theme?.qsDisc ?? "#3A3A3C") ?? (root.theme?.qsDisc ?? "#3A3A3C"))
            stiffness: 5
            damping: 0.6
        }
        MorphDot {
            id: cookie
            property string fromKind: root.shape
            property string toKind: root.shape
            property real p: 1
            property real leap: 0
            Behavior on leap { Spring { stiffness: 5; damp: 0.45; eps: 0.002 } }
            visible: root.shape !== ""
            anchors.centerIn: parent
            width: Math.round(disc.d * 1.12)
            height: width
            scale: leapBump.value
            color: discColor.value
            from: cookie.fromKind
            to: cookie.toKind
            t: cookie.p
            turn: cookie.leap
            function leapTo(kind: string): void {
                cookie.fromKind = cookie.p > 0.5 ? cookie.toKind : cookie.fromKind;
                cookie.toKind = kind;
                morph.restart();
                cookie.leap += Math.PI / 2;
                leapBump.bump();
            }
            GlyphBump {
                id: leapBump
                peak: 1.15
            }
            Spring {
                id: morph
                target: cookie
                property: "p"
                from: 0
                to: 1
                stiffness: 5
                damp: 0.5
                eps: 0.005
            }
            // Slow turn (12 s per revolution) while on or busy; stops in place.
            FrameAnimation {
                running: cookie.visible && (root.spinning || root.busy)
                onTriggered: cookie.rotation = (cookie.rotation + frameTime * 30) % 360
            }
            Timer {
                interval: 800
                repeat: true
                triggeredOnStart: true
                running: cookie.visible && root.busy
                onTriggered: {
                    const pool = MorphShape.RANDOM.filter(k => k !== cookie.toKind);
                    cookie.leapTo(pool[Math.floor(Math.random() * pool.length)]);
                }
            }
            Connections {
                target: root
                function onBusyChanged(): void {
                    if (!root.busy && cookie.visible && cookie.toKind !== root.shape)
                        cookie.leapTo(root.shape);
                }
            }
        }
        Icon {
            anchors.centerIn: parent
            text: root.glyph
            font.family: root.theme?.iconFamily ?? "tabler-icons"
            iconSize: root.pc.glyphSize ?? 20
            iconColor: "white"
        }
        MouseArea {
            id: discMa
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggled()
        }
    }

    Column {
        x: disc.x + disc.width + 12
        width: (trail.width > 0 ? trail.x - 8 : root.width - root.pad) - x
        y: Math.round((root.height - 1 - height) / 2)
        spacing: 1
        Text {
            width: parent.width
            text: root.title
            color: "white"
            font.pixelSize: root.pc.titleSize ?? 17
            font.weight: Font.DemiBold
        }
        BlurSurface {
            id: statusSurface
            property real p: 1
            property string shown: ""
            Component.onCompleted: statusSurface.shown = root.status
            width: parent.width
            height: statusText.implicitHeight
            amount: statusSurface.p < 0.99 ? 1 - Math.max(0, statusSurface.p) : 0
            opacity: Math.max(0, Math.min(1, statusSurface.p))
            transform: Translate { y: (1 - statusSurface.p) * 4 }
            Text {
                id: statusText
                width: parent.width
                text: statusSurface.shown
                color: root.theme?.cardDim ?? "#99EBEBF5"
                font.pixelSize: (root.pc.textSize ?? 14) - 2
                elide: Text.ElideRight
            }
        }
    }

    Connections {
        target: root
        function onStatusChanged(): void {
            if (root.status !== statusSurface.shown)
                statusSwap.restart();
        }
    }
    SequentialAnimation {
        id: statusSwap
        Spring { target: statusSurface; property: "p"; to: 0; stiffness: 9; damp: 0.9; eps: 0.05 }
        ScriptAction { script: statusSurface.shown = root.status }
        Spring { target: statusSurface; property: "p"; to: 1; stiffness: 6; damp: 0.6; eps: 0.005 }
    }

    Row {
        id: trail
        anchors.right: parent.right
        anchors.rightMargin: root.pad - 6
        y: Math.round((root.height - 1 - height) / 2)
        spacing: 2
    }

    Rectangle {
        anchors.bottom: parent.bottom
        x: root.pad
        width: root.width - 2 * root.pad
        height: 1
        color: root.theme?.launcherDivider ?? "#2EFFFFFF"
    }
}
