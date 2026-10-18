import QtQuick
import "../../../components"
import "../../../config"

// Pill text field of the Wi‑Fi panel (password, user name, hidden SSID):
// placeholder, `password` = masked with an eye toggle. Enter = `accepted`,
// Esc = `escaped`, Tab moves on like any focus chain.
Rectangle {
    id: root
    property var pc: ({})
    property var theme: null
    property var frost: null
    property string placeholder: ""
    property bool password: false
    property alias text: input.text
    property alias field: input
    property bool revealed: false
    signal accepted
    signal escaped

    function focusField(): void {
        input.forceActiveFocus();
    }
    function clear(): void {
        input.text = "";
        root.revealed = false;
    }

    radius: height / 2
    color: root.frost?.layerColor(root.theme?.qsDisc ?? "#3A3A3C") ?? (root.theme?.qsDisc ?? "#3A3A3C")

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: root.password ? eye.width + 4 : 14
        verticalAlignment: TextInput.AlignVCenter
        echoMode: root.password && !root.revealed ? TextInput.Password : TextInput.Normal
        color: "white"
        selectionColor: root.theme?.qsBlue ?? "#017EFC"
        font.pixelSize: (root.pc.textSize ?? 14) - 1
        clip: true
        activeFocusOnTab: true
        onAccepted: root.accepted()
        Keys.onEscapePressed: root.escaped()

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text.length === 0
            text: root.placeholder
            color: root.theme?.cardDim ?? "#99EBEBF5"
            font.pixelSize: input.font.pixelSize
        }
    }

    PanelButton {
        id: eye
        visible: root.password
        anchors.right: parent.right
        anchors.rightMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        size: root.height - 4
        pc: root.pc
        theme: root.theme
        frost: root.frost
        // tabler eye-off / eye
        glyph: root.revealed ? "" : ""
        onClicked: {
            root.revealed = !root.revealed;
            input.forceActiveFocus();
        }
    }
}
