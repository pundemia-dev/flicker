import QtQuick
import "../../../components"
import "../../../config"

// One output / input device of the audio panel (AudioGraph row): kind
// glyph, name, state line, check on the current device. Tap = make it the
// current one (a port / profile switch when it has no node yet). The
// current device unfolds a volume slider (input: + live level) and, for a
// Bluetooth headset that can do both, the Music / Calls profile pills.
Item {
    id: root
    required property Item panel
    property var row: ({})
    property bool sink: true

    readonly property var pc: root.panel.pc
    readonly property var theme: root.panel.theme
    readonly property var audio: root.panel.audio
    readonly property real rowH: root.pc.rowHeight ?? 42
    readonly property bool current: root.row?.isDefault ?? false
    readonly property bool usable: root.row?.available ?? false
    readonly property var modes: root.current && root.row?.bt?.card ? root.panel.model.btModes(root.row.bt.card) : null

    readonly property var btDevice: {
        const a = (root.row?.bt?.address ?? "").toUpperCase();
        if (a === "")
            return null;
        return (root.panel.services?.bluetooth?.adapter?.devices?.values ?? []).find(d => `${d.address}`.toUpperCase() === a) ?? null;
    }

    readonly property string stateText: {
        const r = root.row ?? {};
        if (r.sub === "unplugged")
            return I18n.tr("Not plugged in");
        if (r.sub === "callMode")
            return I18n.tr("Switches to call mode");
        const parts = [];
        if (r.bt) {
            parts.push(root.modes?.active === "calls" ? I18n.tr("Calls") : "Bluetooth");
            if (root.btDevice?.batteryAvailable)
                parts.push(`${Math.round(root.btDevice.battery * 100)}%`);
        }
        if (root.current && (root.sink ? root.audio?.muted : root.audio?.sourceMuted))
            parts.push(I18n.tr("Muted"));
        return parts.join(" · ");
    }

    readonly property real extraH: root.current ? slider.height + 10 + (root.modes ? pills.height + 10 : 0) : 0
    height: root.rowH + root.extraH
    Behavior on height { Spring { stiffness: 6; damp: 0.6; eps: 0.3 } }
    clip: true

    Rectangle {
        x: 6
        width: parent.width - 12
        height: root.rowH
        radius: height / 2
        color: root.panel.frost?.layerColor(root.theme?.qsDisc ?? "#3A3A3C") ?? (root.theme?.qsDisc ?? "#3A3A3C")
        opacity: !root.usable || root.current ? 0 : ma.pressed ? 0.8 : ma.containsMouse ? 0.45 : 0
        Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
    }
    MouseArea {
        id: ma
        width: parent.width
        height: root.rowH
        hoverEnabled: true
        cursorShape: root.usable && !root.current ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (!root.current) root.panel.model.choose(root.row, root.sink)
    }

    Item {
        width: parent.width
        height: root.rowH
        opacity: root.usable ? 1 : 0.45

        Icon {
            id: glyph
            x: root.panel.pad
            width: root.pc.glyphSize ?? 20
            height: root.rowH
            text: root.panel.glyphOf(root.row?.kind ?? (root.sink ? "speaker" : "mic"))
            font.family: root.theme?.iconFamily ?? "tabler-icons"
            iconSize: root.pc.glyphSize ?? 20
            iconColor: root.current ? (root.theme?.qsBlue ?? "#017EFC") : "white"
        }
        Column {
            x: glyph.x + glyph.width + 12
            width: check.x - x - 8
            y: Math.round((root.rowH - height) / 2)
            Text {
                width: parent.width
                text: root.row?.translate ? I18n.tr(root.row.label) : (root.row?.label ?? "")
                color: "white"
                font.pixelSize: root.pc.textSize ?? 14
                font.weight: root.current ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: root.stateText !== ""
                text: root.stateText
                color: root.theme?.cardDim ?? "#99EBEBF5"
                font.pixelSize: (root.pc.textSize ?? 14) - 3
                elide: Text.ElideRight
            }
        }
        Icon {
            id: check
            anchors.right: parent.right
            anchors.rightMargin: root.panel.pad
            height: root.rowH
            opacity: root.current ? 1 : 0
            scale: root.current ? 1 : 0.5
            Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
            Behavior on scale { Spring { stiffness: 6; damp: 0.45; eps: 0.005 } }
            text: ""
            font.family: root.theme?.iconFamily ?? "tabler-icons"
            iconSize: (root.pc.glyphSize ?? 20) - 2
            iconColor: root.theme?.qsBlue ?? "#017EFC"
        }
    }

    // Current device: its volume (output scaled to audio.maxVolume, like
    // the QS volume card; quiet() = no OSD for Quick Settings changes).
    PanelSlider {
        id: slider
        x: root.panel.pad
        y: root.rowH + 2
        width: parent.width - 2 * root.panel.pad
        pc: root.pc
        theme: root.theme
        frost: root.panel.frost
        opacity: root.current ? 1 : 0
        Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
        wheelStep: root.panel.cfg?.wheelStep ?? 0.05
        glyph: root.sink ? "" : ""
        mutedGlyph: root.sink ? "" : ""
        readonly property real max: root.sink ? (root.audio?.maxVolume ?? 1) : 1
        value: (root.sink ? root.audio?.volume ?? 0 : root.audio?.sourceVolume ?? 0) / max
        muted: root.sink ? (root.audio?.muted ?? false) : (root.audio?.sourceMuted ?? false)
        level: root.sink || !root.current ? -1 : root.panel.micLevel
        onMoved: v => {
            root.audio?.quiet();
            if (root.sink)
                root.audio?.setVolume(v * max);
            else
                root.audio?.setSourceVolume(v * max);
        }
        onMuteToggled: {
            root.audio?.quiet();
            if (root.sink)
                root.audio?.toggleMute();
            else
                root.audio?.toggleSourceMute();
        }
    }

    // Bluetooth headset: music (A2DP, quality) or calls (headset profile,
    // with its microphone).
    Row {
        id: pills
        x: root.panel.pad
        y: slider.y + slider.height + 10
        height: (root.pc.fieldHeight ?? 34) - 4
        spacing: 6
        opacity: root.modes ? 1 : 0
        Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
        PanelPill {
            height: parent.height
            pc: root.pc
            theme: root.theme
            frost: root.panel.frost
            text: I18n.tr("Music")
            checked: root.modes?.active === "music"
            onClicked: if (root.modes && !checked) root.panel.model.setProfile(root.row.bt.card, root.modes.music)
        }
        PanelPill {
            height: parent.height
            pc: root.pc
            theme: root.theme
            frost: root.panel.frost
            text: I18n.tr("Calls")
            checked: root.modes?.active === "calls"
            onClicked: if (root.modes && !checked) root.panel.model.setProfile(root.row.bt.card, root.modes.calls)
        }
    }
}
