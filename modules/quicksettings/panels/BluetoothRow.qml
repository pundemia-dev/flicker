import QtQuick
import Quickshell.Bluetooth
import "../../../components"
import "../../../config"

// One device in the Bluetooth panel: kind glyph (BlueZ icon name), name,
// state line (connecting / pairing / battery), check when connected.
Item {
    id: root
    required property Item panel
    property var device: null

    readonly property var pc: root.panel.pc
    readonly property var theme: root.panel.theme
    readonly property real rowH: root.pc.rowHeight ?? 42
    readonly property int st: root.device?.state ?? BluetoothDeviceState.Disconnected
    readonly property bool connected: root.device?.connected ?? false
    // Pair requested from here: connect once BlueZ reports it paired.
    property bool joinAfterPair: false

    height: root.rowH

    function kindGlyph(icon: string): string {
        if (/headset/.test(icon))
            return "";
        if (/audio|head|speaker/.test(icon))
            return "";
        if (/mouse/.test(icon))
            return "";
        if (/keyboard/.test(icon))
            return "";
        if (/gaming|joystick/.test(icon))
            return "";
        if (/phone/.test(icon))
            return "";
        if (/computer|laptop/.test(icon))
            return "";
        return "";
    }

    function tap(): void {
        const d = root.device;
        if (!d || d.pairing || root.st === BluetoothDeviceState.Connecting || root.st === BluetoothDeviceState.Disconnecting)
            return;
        if (d.connected)
            d.disconnect();
        else if (d.paired)
            d.connect();
        else {
            root.joinAfterPair = true;
            d.pair();
        }
    }
    Connections {
        target: root.device
        function onPairedChanged(): void {
            if (root.joinAfterPair && root.device.paired) {
                root.joinAfterPair = false;
                root.device.trusted = true;
                root.device.connect();
            }
        }
    }

    readonly property string stateText: {
        const d = root.device;
        if (!d)
            return "";
        if (d.pairing)
            return I18n.tr("Pairing…");
        if (root.st === BluetoothDeviceState.Connecting)
            return I18n.tr("Connecting…");
        if (root.st === BluetoothDeviceState.Disconnecting)
            return I18n.tr("Disconnecting…");
        if (d.connected)
            return d.batteryAvailable ? I18n.tr("Connected · %1%").arg(Math.round(d.battery * 100)) : I18n.tr("Connected");
        return d.paired ? I18n.tr("Not connected") : "";
    }

    Rectangle {
        x: 6
        width: parent.width - 12
        height: root.rowH
        radius: height / 2
        color: root.panel.frost?.layerColor(root.theme?.qsDisc ?? "#3A3A3C") ?? (root.theme?.qsDisc ?? "#3A3A3C")
        opacity: ma.pressed ? 0.8 : ma.containsMouse ? 0.45 : 0
        Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.tap()
    }

    Icon {
        id: glyph
        x: root.panel.pad
        width: root.pc.glyphSize ?? 20
        height: root.rowH
        text: root.kindGlyph(root.device?.icon ?? "")
        font.family: root.theme?.iconFamily ?? "tabler-icons"
        iconSize: root.pc.glyphSize ?? 20
        iconColor: "white"
    }

    Column {
        x: glyph.x + glyph.width + 12
        width: check.x - x - 8
        y: Math.round((root.rowH - height) / 2)
        Text {
            width: parent.width
            text: root.device?.name ?? ""
            color: "white"
            font.pixelSize: root.pc.textSize ?? 14
            font.weight: root.connected ? Font.DemiBold : Font.Normal
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
        opacity: root.connected ? 1 : 0
        text: ""
        font.family: root.theme?.iconFamily ?? "tabler-icons"
        iconSize: (root.pc.glyphSize ?? 20) - 2
        iconColor: root.theme?.qsBlue ?? "#017EFC"
    }
}
