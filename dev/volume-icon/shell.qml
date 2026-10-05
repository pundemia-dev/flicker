import QtQuick
import Quickshell
import Quickshell.Io
import "components"

// Dev preview of components/VolumeIcon.qml (not part of the shell):
//   quickshell -p dev/volume-icon/shell.qml
// Row 1 = every static variant, row 2 = every animation on a loop
// (click a tile to replay it right away). `components` is a symlink, which
// quickshell's own watcher does not follow — the FileViews below reload
// the preview whenever the icon's files change.
FloatingWindow {
    id: win

    Variants {
        model: ["components/VolumeIcon.qml", "components/VolumeGeometry.js", "components/Spring.qml"]
        FileView {
            required property string modelData
            path: Quickshell.shellDir + "/" + modelData
            watchChanges: true
            onFileChanged: Quickshell.reload(false)
        }
    }
    title: "VolumeIcon preview"
    implicitWidth: 1280
    implicitHeight: 560
    color: "#0E0F12"

    readonly property real iconSize: 110
    readonly property color ink: "#E9ECF1"

    component Tile: Rectangle {
        id: tile
        property string label
        property string note
        default property alias content: slot.data
        signal tapped
        width: 150
        height: 210
        radius: 22
        color: "#000000"
        Item {
            id: slot
            width: parent.width
            height: 150
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 150
            width: parent.width - 12
            horizontalAlignment: Text.AlignHCenter
            text: tile.label
            color: "#E9ECF1"
            font.family: "SF Pro Display"
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 172
            width: parent.width - 12
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: tile.note
            color: "#8A919C"
            font.family: "SF Pro Display"
            font.pixelSize: 11
        }
        MouseArea {
            anchors.fill: parent
            onClicked: tile.tapped()
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 22

        Text {
            text: "Варианты"
            color: "#8A919C"
            font.family: "SF Pro Display"
            font.pixelSize: 15
        }
        Row {
            spacing: 6
            Tile {
                label: "0 дуг"
                VolumeIcon { anchors.centerIn: parent; size: win.iconSize; color: win.ink; arcs: 0 }
            }
            Tile {
                label: "1 дуга"
                VolumeIcon { anchors.centerIn: parent; size: win.iconSize; color: win.ink; arcs: 1 }
            }
            Tile {
                label: "2 дуги"
                VolumeIcon { anchors.centerIn: parent; size: win.iconSize; color: win.ink; arcs: 2 }
            }
            Tile {
                label: "3 дуги"
                VolumeIcon { anchors.centerIn: parent; size: win.iconSize; color: win.ink; arcs: 3 }
            }
            Tile {
                label: "mute"
                note: "OSD: дуг нет"
                VolumeIcon { anchors.centerIn: parent; size: win.iconSize; color: win.ink; arcs: 0; muted: true }
            }
            Tile {
                label: "mute + 3 дуги"
                VolumeIcon { anchors.centerIn: parent; size: win.iconSize; color: win.ink; arcs: 3; muted: true }
            }
            Tile {
                label: "maxArcs: 0"
                note: "QS слева"
                VolumeIcon { anchors.centerIn: parent; size: win.iconSize; color: win.ink; maxArcs: 0; arcs: 0 }
            }
            Tile {
                label: "maxArcs: 0, mute"
                note: "QS слева, mute"
                VolumeIcon { anchors.centerIn: parent; size: win.iconSize; color: win.ink; maxArcs: 0; arcs: 0; muted: true }
            }
        }

        Text {
            text: "Анимации (по кругу, клик — повторить сразу)"
            color: "#8A919C"
            font.family: "SF Pro Display"
            font.pixelSize: 15
        }
        Row {
            spacing: 6
            Tile {
                id: tArcs
                label: "дуги 0→3→0"
                note: "fade + сдвиг"
                property int step: 0
                readonly property var seq: [0, 1, 2, 3, 2, 1]
                function next(): void { step = (step + 1) % seq.length; }
                onTapped: next()
                VolumeIcon { anchors.centerIn: parent; size: win.iconSize; color: win.ink; arcs: tArcs.seq[tArcs.step] }
            }
            Tile {
                id: tMute
                label: "mute"
                note: "дуги гаснут + линия"
                property bool on: false
                function next(): void { on = !on; }
                onTapped: next()
                VolumeIcon { anchors.centerIn: parent; size: win.iconSize; color: win.ink; arcs: tMute.on ? 0 : 2; muted: tMute.on }
            }
            Tile {
                id: tMute3
                label: "mute (3 дуги)"
                note: "только линия"
                property bool on: false
                function next(): void { on = !on; }
                onTapped: next()
                VolumeIcon { anchors.centerIn: parent; size: win.iconSize; color: win.ink; arcs: 3; muted: tMute3.on }
            }
            Tile {
                id: tPulse
                label: "pulse()"
                note: "QS слева: громкость 0"
                function next(): void { pulseIcon.pulse(); }
                onTapped: next()
                VolumeIcon { id: pulseIcon; anchors.centerIn: parent; size: win.iconSize; color: win.ink; maxArcs: 0; arcs: 0 }
            }
            Tile {
                id: tWave
                label: "wave()"
                note: "QS справа: громкость 100"
                function next(): void { waveIcon.wave(); }
                onTapped: next()
                VolumeIcon { id: waveIcon; anchors.centerIn: parent; size: win.iconSize; color: win.ink; arcs: 3 }
            }
            Tile {
                id: tOsd
                label: "OSD-сценарий"
                note: "50→0 (pulse)→100 (wave)→mute"
                property int step: 0
                // [arcs, muted, accent]
                readonly property var seq: [[2, false, ""], [1, false, ""], [0, false, "pulse"], [1, false, ""], [2, false, ""], [3, false, "wave"], [0, true, ""], [2, false, ""]]
                function next(): void {
                    step = (step + 1) % seq.length;
                    const a = seq[step][2];
                    if (a === "pulse") osdIcon.pulse();
                    if (a === "wave") osdIcon.wave();
                }
                onTapped: next()
                VolumeIcon { id: osdIcon; anchors.centerIn: parent; size: win.iconSize; color: win.ink; arcs: tOsd.seq[tOsd.step][0]; muted: tOsd.seq[tOsd.step][1] }
            }
            Tile {
                id: tTrans
                label: "полупрозрачный"
                note: "#B3EBEBF5 (как в QS), mute"
                property bool on: false
                function next(): void { on = !on; }
                onTapped: next()
                VolumeIcon { anchors.centerIn: parent; size: win.iconSize; color: "#B3EBEBF5"; arcs: tTrans.on ? 0 : 3; muted: tTrans.on }
            }
        }
    }

    Timer {
        interval: 1400
        repeat: true
        running: true
        onTriggered: {
            tArcs.next();
            tMute.next();
            tMute3.next();
            tPulse.next();
            tWave.next();
            tOsd.next();
            tTrans.next();
        }
    }
}
