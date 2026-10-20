import QtQuick
import Quickshell.Services.Pipewire
import "../../../components"
import "../../../config"
import "PanelSync.js" as PanelSync

// Audio panel (DropExpand panel from the media card's output button): the
// everyday sound controls; the rest lives in the settings window (header
// button). Header disc = output mute. Sections:
//   Output  one row per physical device (AudioGraph: a DSP filter-chain and
//           its raw device are one "Speakers"); tap = switch; the current
//           one unfolds its volume, a Bluetooth headset the Music / Calls
//           profile pills. Unplugged headphones show dimmed.
//   Input   same for microphones; the current one has its gain + a live
//           level meter (PwNodePeakMonitor, only while this panel exists).
//   Apps    every app playing sound: own volume / mute, the output it plays
//           to (tap = move it elsewhere); "System sounds" (the shell's own
//           pw-play sounds, audio.eventVolume); who is using the microphone
//           (pills, tap = mute that app's capture).
Item {
    id: root
    property var services: null
    property var cfg: null
    property var theme: null
    property var frost: null
    property var expander: null
    signal closeRequested

    readonly property var audio: root.services?.audio ?? null
    readonly property var pc: root.cfg?.listPanel ?? ({})
    readonly property real pad: root.pc.padding ?? 18
    readonly property real rowH: root.pc.rowHeight ?? 42
    readonly property color dimColor: root.theme?.cardDim ?? "#99EBEBF5"
    // Stream whose output pills are unfolded (-1 = none).
    property int openStream: -1

    // services/AudioDevices (shared with settings and AudioPolicy).
    readonly property var model: root.services?.audioDevices ?? null

    PwNodePeakMonitor {
        id: peak
        node: root.audio?.source ?? null
        enabled: root.visible && !(root.audio?.sourceMuted ?? true)
    }
    readonly property real micLevel: peak.peak

    function glyphOf(kind: string): string {
        return ({
            speaker: "", mic: "", headphones: "", headset: "",
            usb: "", usbHeadset: "", btHeadphones: "", btHeadset: "",
            btSpeaker: "", hdmi: ""
        })[kind] ?? "";
    }

    // Row identity only; rows look their live data up by key / id (no
    // copies in the models — a reassigned array rebuilt every delegate).
    onOutputListChanged: PanelSync.sync(outRows, root.outputList, "key")
    onInputListChanged: PanelSync.sync(inRows, root.inputList, "key")
    onStreamListChanged: {
        PanelSync.sync(streamRows, root.streamList, "key");
        if (!(root.model?.streams ?? []).some(s => s.id === root.openStream))
            root.openStream = -1;
    }
    readonly property var outputList: (root.model?.outputs ?? []).map(r => ({ key: r.key }))
    readonly property var inputList: (root.model?.inputs ?? []).map(r => ({ key: r.key }))
    readonly property var streamList: (root.model?.streams ?? []).map(s => ({ key: `${s.id}` }))
    ListModel { id: outRows }
    ListModel { id: inRows }
    ListModel { id: streamRows }

    readonly property var current: root.model?.currentOutput ?? null

    // Debug IPC (island quicksettingsPanel <cmd> <arg>): "scroll" <px>,
    // anything else = the rows as JSON.
    function debug(cmd: string, arg: string): string {
        if (cmd === "scroll")
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, Number(arg) || 0));
        return JSON.stringify({ outputs: root.model?.outputs, inputs: root.model?.inputs, streams: root.model?.streams });
    }

    PanelHeader {
        id: header
        width: parent.width
        pc: root.pc
        theme: root.theme
        frost: root.frost
        pad: root.pad
        on: !(root.audio?.muted ?? false)
        glyph: on ? "" : ""
        title: I18n.tr("Sound")
        status: {
            const name = root.current ? (root.current.translate ? I18n.tr(root.current.label) : root.current.label) : I18n.tr("No output");
            return root.audio?.muted ? `${name} · ${I18n.tr("Muted")}` : name;
        }
        onToggled: {
            root.audio?.quiet();
            root.audio?.toggleMute();
        }
        trailing: [
            PanelButton {
                pc: root.pc
                theme: root.theme
                frost: root.frost
                glyph: ""
                onClicked: {
                    root.services?.openSettings?.("sound");
                    root.closeRequested();
                }
            }
        ]
    }

    component SectionTitle: Text {
        x: root.pad
        width: parent.width - 2 * root.pad
        height: 28
        verticalAlignment: Text.AlignBottom
        bottomPadding: 4
        color: root.dimColor
        font.pixelSize: (root.pc.textSize ?? 14) - 3
        font.weight: Font.DemiBold
    }

    Flickable {
        id: flick
        y: header.height
        width: parent.width
        height: parent.height - y
        clip: true
        contentHeight: body.height + 12
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: body
            width: flick.width

            SectionTitle { text: I18n.tr("Output") }
            Repeater {
                model: outRows
                delegate: AudioDeviceRow {
                    required property var model
                    width: body.width
                    panel: root
                    sink: true
                    row: root.model.outputs.find(r => r.key === model.key) ?? ({})
                }
            }

            SectionTitle { text: I18n.tr("Input") }
            Repeater {
                model: inRows
                delegate: AudioDeviceRow {
                    required property var model
                    width: body.width
                    panel: root
                    sink: false
                    row: root.model.inputs.find(r => r.key === model.key) ?? ({})
                }
            }
            Text {
                visible: inRows.count === 0
                x: root.pad
                height: root.rowH
                verticalAlignment: Text.AlignVCenter
                text: I18n.tr("No microphone")
                color: root.dimColor
                font.pixelSize: root.pc.textSize ?? 14
            }

            SectionTitle { text: I18n.tr("Apps") }
            Repeater {
                model: streamRows
                delegate: AudioStreamRow {
                    required property var model
                    width: body.width
                    panel: root
                    stream: root.model.streams.find(s => `${s.id}` === model.key) ?? ({})
                }
            }
            Text {
                visible: streamRows.count === 0
                x: root.pad
                height: root.rowH - 6
                verticalAlignment: Text.AlignVCenter
                text: I18n.tr("Nothing is playing")
                color: root.dimColor
                font.pixelSize: root.pc.textSize ?? 14
            }

            // The shell's own sounds (notifications): audio.eventVolume,
            // saved once the slider rests; mute remembers the level.
            Item {
                id: events
                width: body.width
                height: root.rowH + eventSlider.height + 4
                readonly property real saved: Config.data.audio.eventVolume ?? 1
                property real local: events.saved
                property real lastAudible: events.saved > 0 ? events.saved : 1
                onSavedChanged: if (!saveTimer.running) events.local = events.saved
                function store(v: real): void {
                    events.local = v;
                    if (v > 0)
                        events.lastAudible = v;
                    saveTimer.restart();
                }
                Timer {
                    id: saveTimer
                    interval: 400
                    onTriggered: Config.set("audio.eventVolume", Math.round(events.local * 100) / 100)
                }
                Icon {
                    id: bell
                    x: root.pad
                    width: root.pc.glyphSize ?? 20
                    height: root.rowH
                    text: ""
                    font.family: root.theme?.iconFamily ?? "tabler-icons"
                    iconSize: root.pc.glyphSize ?? 20
                    iconColor: "white"
                }
                Text {
                    x: bell.x + bell.width + 12
                    height: root.rowH
                    verticalAlignment: Text.AlignVCenter
                    text: I18n.tr("System sounds")
                    color: "white"
                    font.pixelSize: root.pc.textSize ?? 14
                    font.weight: Font.DemiBold
                }
                PanelSlider {
                    id: eventSlider
                    x: root.pad
                    y: root.rowH - 2
                    width: parent.width - 2 * root.pad
                    pc: root.pc
                    theme: root.theme
                    frost: root.frost
                    wheelStep: root.cfg?.wheelStep ?? 0.05
                    glyph: ""
                    mutedGlyph: ""
                    value: events.local
                    muted: events.local <= 0
                    onMoved: v => events.store(v)
                    onMuteToggled: events.store(events.local > 0 ? 0 : events.lastAudible)
                }
            }

            // Apps capturing the microphone (Audio.captureStreams: the
            // shell's own capture is already filtered out).
            Item {
                width: body.width
                visible: (root.audio?.captureStreams ?? []).length > 0
                height: visible ? root.rowH + micFlow.height + 6 : 0
                Icon {
                    id: micGlyph
                    x: root.pad
                    width: root.pc.glyphSize ?? 20
                    height: root.rowH
                    text: ""
                    font.family: root.theme?.iconFamily ?? "tabler-icons"
                    iconSize: root.pc.glyphSize ?? 20
                    iconColor: root.theme?.qsOrange ?? "#FF9F0A"
                }
                Text {
                    x: micGlyph.x + micGlyph.width + 12
                    height: root.rowH
                    verticalAlignment: Text.AlignVCenter
                    text: I18n.tr("Using the microphone")
                    color: "white"
                    font.pixelSize: root.pc.textSize ?? 14
                    font.weight: Font.DemiBold
                }
                Flow {
                    id: micFlow
                    x: root.pad
                    y: root.rowH - 4
                    width: parent.width - 2 * root.pad
                    spacing: 6
                    Repeater {
                        model: root.audio?.captureStreams ?? []
                        delegate: PanelPill {
                            required property var modelData
                            height: (root.pc.fieldHeight ?? 34) - 4
                            pc: root.pc
                            theme: root.theme
                            frost: root.frost
                            readonly property bool muted: modelData?.audio?.muted ?? false
                            text: muted ? `${root.audio.streamLabel(modelData)} · ${I18n.tr("Muted")}` : root.audio.streamLabel(modelData)
                            danger: muted
                            checked: muted
                            onClicked: {
                                if (modelData?.audio)
                                    modelData.audio.muted = !modelData.audio.muted;
                            }
                        }
                    }
                }
            }
        }
    }
}
