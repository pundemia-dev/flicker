import QtQuick
import "../../components"

// Password pill: key glyph, masked input (plain when polkit asks for a
// visible response), eye toggle, busy dim while PAM checks. Shakes on a
// wrong password (iOS): `shake()` kicks a Translate that springs back to 0
// with low damping, so it rings out instead of a timed wobble.
Rectangle {
    id: root
    required property var theme
    required property var cfg
    property string placeholder: "Пароль"
    property bool plainText: false
    property bool busy: false
    property bool error: false
    readonly property alias text: input.text
    property bool reveal: false
    signal accepted
    signal escaped

    function clear(): void {
        input.text = "";
    }

    function focusField(): void {
        input.forceActiveFocus();
    }

    function shake(): void {
        shakeAnim.restart();
    }

    height: root.cfg.fieldHeight
    radius: height / 2
    color: root.theme.cardBg
    border.width: 1
    border.color: Qt.alpha(root.theme.accentRed, root.errorAlpha)
    property real errorAlpha: root.error ? 0.8 : 0
    Behavior on errorAlpha { Spring { eps: 0.01 } }

    transform: Translate { id: shift }

    SpringAnimation {
        id: shakeAnim
        target: shift
        property: "x"
        from: root.cfg.shakeKick
        to: 0
        spring: root.cfg.shakeSpring
        damping: root.cfg.shakeDamping
        epsilon: 0.2
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onClicked: input.forceActiveFocus()
    }

    Text {
        id: glyph
        x: (root.height - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        text: "" // tabler lock
        font.family: root.theme.iconFamily
        font.pixelSize: root.cfg.fieldIconSize
        color: root.theme.cardDim
    }

    TextInput {
        id: input
        anchors.left: parent.left
        anchors.leftMargin: root.height
        anchors.right: eye.left
        anchors.rightMargin: root.cfg.gap / 2
        anchors.verticalCenter: parent.verticalCenter
        color: root.theme.islandFg
        selectionColor: root.theme.qsBlue
        selectedTextColor: root.theme.islandFg
        font.family: root.theme.fontFamily
        font.pixelSize: root.cfg.fontSize
        echoMode: root.plainText || root.reveal ? TextInput.Normal : TextInput.Password
        passwordCharacter: "•"
        enabled: !root.busy
        opacity: root.busy ? 0.5 : 1
        Behavior on opacity { Spring { eps: 0.01 } }
        clip: true
        focus: true

        onAccepted: root.accepted()
        Keys.onEscapePressed: root.escaped()

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.busy ? "Проверка…" : root.placeholder
            color: root.theme.cardDim
            font: input.font
            visible: input.text.length === 0
        }
    }

    // Show / hide the typed password (hidden when the response is plain anyway).
    Text {
        id: eye
        anchors.right: parent.right
        anchors.rightMargin: (root.height - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        width: root.plainText ? 0 : root.cfg.fieldIconSize
        horizontalAlignment: Text.AlignHCenter
        text: root.reveal ? "" : "" // tabler eye-off / eye
        font.family: root.theme.iconFamily
        font.pixelSize: root.cfg.fieldIconSize
        color: root.theme.cardDim
        opacity: input.text.length === 0 || root.plainText ? 0 : (eyeMa.containsMouse ? 1 : 0.7)
        Behavior on opacity { Spring { eps: 0.01 } }

        MouseArea {
            id: eyeMa
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            enabled: input.text.length > 0
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.reveal = !root.reveal;
                input.forceActiveFocus();
            }
        }
    }
}
