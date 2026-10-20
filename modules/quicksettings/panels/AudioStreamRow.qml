import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../../components"
import "../../../config"

// One app playing sound (mixer row of the audio panel): app icon, name +
// what it plays, its own volume (tap the slider glyph = mute it). The
// trailing glyph = the output it plays to; with more than one output, a tap
// unfolds those outputs as pills — a tap moves the app there (WirePlumber
// remembers it for the app).
Item {
    id: root
    required property Item panel
    property var stream: ({})

    readonly property var pc: root.panel.pc
    readonly property var theme: root.panel.theme
    readonly property real rowH: root.pc.rowHeight ?? 42
    readonly property var node: root.panel.model.node(root.stream?.id ?? -1)
    readonly property var outputs: root.panel.model.outputs.filter(r => r.nodeId >= 0)
    readonly property var target: root.outputs.find(r => r.key === root.stream?.targetKey) ?? null
    readonly property bool routable: root.outputs.length > 1
    readonly property bool routeOpen: root.panel.openStream === (root.stream?.id ?? -1) && root.routable

    height: root.rowH + slider.height + 4 + (root.routeOpen ? pills.height + 10 : 0)
    Behavior on height { Spring { stiffness: 6; damp: 0.6; eps: 0.3 } }
    clip: true

    readonly property string iconSource: {
        const name = root.stream?.icon ?? "";
        if (name === "")
            return "";
        const entry = DesktopEntries.heuristicLookup(name);
        return Quickshell.iconPath(entry?.icon || name, true);
    }

    Item {
        id: lead
        x: root.panel.pad - 1
        width: (root.pc.glyphSize ?? 20) + 2
        height: root.rowH
        IconImage {
            anchors.centerIn: parent
            implicitSize: parent.width
            visible: root.iconSource !== ""
            source: root.iconSource
            asynchronous: true
        }
        Icon {
            anchors.fill: parent
            visible: root.iconSource === ""
            text: ""
            font.family: root.theme?.iconFamily ?? "tabler-icons"
            iconSize: root.pc.glyphSize ?? 20
            iconColor: "white"
        }
    }
    Column {
        x: lead.x + lead.width + 11
        width: route.x - x - 6
        y: Math.round((root.rowH - height) / 2)
        Text {
            width: parent.width
            text: root.stream?.app ?? ""
            color: "white"
            font.pixelSize: root.pc.textSize ?? 14
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            visible: text !== "" && text !== root.stream?.app
            text: root.stream?.media ?? ""
            color: root.theme?.cardDim ?? "#99EBEBF5"
            font.pixelSize: (root.pc.textSize ?? 14) - 3
            elide: Text.ElideRight
        }
    }
    PanelButton {
        id: route
        anchors.right: parent.right
        anchors.rightMargin: root.panel.pad - 6
        y: Math.round((root.rowH - height) / 2)
        pc: root.pc
        theme: root.theme
        frost: root.panel.frost
        visible: root.routable
        glyph: root.target ? root.panel.glyphOf(root.target.kind) : ""
        onClicked: root.panel.openStream = root.routeOpen ? -1 : root.stream.id
    }

    PanelSlider {
        id: slider
        x: root.panel.pad
        y: root.rowH - 2
        width: parent.width - 2 * root.panel.pad
        pc: root.pc
        theme: root.theme
        frost: root.panel.frost
        wheelStep: root.panel.cfg?.wheelStep ?? 0.05
        value: root.node?.audio?.volume ?? 0
        muted: root.node?.audio?.muted ?? false
        onMoved: v => {
            if (!root.node?.audio)
                return;
            root.node.audio.muted = false;
            root.node.audio.volume = v;
        }
        onMuteToggled: {
            if (root.node?.audio)
                root.node.audio.muted = !root.node.audio.muted;
        }
    }

    Flow {
        id: pills
        x: root.panel.pad
        y: slider.y + slider.height + 10
        width: parent.width - 2 * root.panel.pad
        spacing: 6
        opacity: root.routeOpen ? 1 : 0
        Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
        Repeater {
            model: root.routeOpen ? root.outputs : []
            delegate: PanelPill {
                required property var modelData
                height: (root.pc.fieldHeight ?? 34) - 4
                pc: root.pc
                theme: root.theme
                frost: root.panel.frost
                text: modelData.translate ? I18n.tr(modelData.label) : modelData.label
                checked: modelData.key === root.stream?.targetKey
                onClicked: {
                    if (!checked)
                        root.panel.model.moveStream(root.stream.serial, modelData.key);
                    root.panel.openStream = -1;
                }
            }
        }
    }
}
