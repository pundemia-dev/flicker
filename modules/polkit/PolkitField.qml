import QtQuick
import "../../components"
import "../../config"

// Password pill: key glyph, masked input (plain when polkit asks for a
// visible response), eye toggle, busy dim while PAM checks. Shakes on a
// wrong password (iOS): `shake()` kicks a Translate that springs back to 0
// with low damping, so it rings out instead of a timed wobble.
Rectangle {
    id: root
    required property var theme
    required property var cfg
    property string placeholder: I18n.tr("Password")
    property bool plainText: false
    property bool busy: false
    property bool error: false
    // pam_faillock lockout: the whole pill turns red, the text sits inside
    // it in place of the placeholder and input is off.
    property bool locked: false
    // Lockout text split by the service: static prefix + rolling value.
    property string lockPrefix: ""
    property string lockValue: ""
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

    onLockedChanged: if (root.locked) input.text = ""

    function shake(): void {
        shakeAnim.restart();
    }

    height: root.cfg.fieldHeight
    radius: height / 2
    color: root.theme.cardBg
    border.width: 1
    border.color: Qt.alpha(root.theme.accentRed, root.errorAlpha * (1 - root.lockAlpha))
    property real errorSpring: root.error ? 0.8 : 0
    Behavior on errorSpring { Spring { eps: 0.01 } }
    readonly property real errorAlpha: Math.max(0, Math.min(1, root.errorSpring))
    property real lockSpring: root.locked ? 1 : 0
    Behavior on lockSpring { Spring { eps: 0.01 } }
    // Springs overshoot past 0..1; colour alphas must stay in range.
    readonly property real lockAlpha: Math.max(0, Math.min(1, root.lockSpring))

    // Red fill of the locked state (fades over the card colour).
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Qt.alpha(root.theme.accentRed, root.cfg.lockFillAlpha * root.lockAlpha)
    }

    // Locked outline: blinks transparent ↔ a shade darker than the red fill
    // (fill = accentRed at lockFillAlpha over the card). A looping timed
    // fade by nature (user decision), not a spring.
    readonly property color lockFillColor: Qt.tint(root.theme.cardBg, Qt.alpha(root.theme.accentRed, root.cfg.lockFillAlpha))
    property real lockPulse: 0
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: "transparent"
        border.width: root.cfg.lockBorderWidth
        border.color: Qt.alpha(Qt.darker(root.lockFillColor, root.cfg.lockBorderDarker), root.lockAlpha * root.lockPulse)
    }
    SequentialAnimation {
        running: root.locked
        loops: Animation.Infinite
        onStopped: root.lockPulse = 0
        NumberAnimation { target: root; property: "lockPulse"; from: 0; to: 1; duration: root.cfg.lockPulseMs / 2; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "lockPulse"; from: 1; to: 0; duration: root.cfg.lockPulseMs / 2; easing.type: Easing.InOutSine }
    }

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
        color: Qt.tint(root.theme.cardDim, Qt.alpha(root.theme.islandFg, root.lockAlpha))
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
        // readOnly, not enabled: a disabled input drops Esc (cancel).
        readOnly: root.busy || root.locked
        opacity: root.busy && !root.locked ? 0.5 : 1
        Behavior on opacity { Spring { eps: 0.01 } }
        clip: true
        focus: true

        onAccepted: if (!readOnly) root.accepted()
        Keys.onEscapePressed: root.escaped()

        // In-field texts: placeholder / checking / lockout, each its own
        // blur-fade layer so a state change crossfades (FadeBlur).
        FadeBlur {
            width: parent.width
            height: parent.height
            blurMax: root.cfg.textBlurMax
            shown: !root.locked && !root.busy && input.text.length === 0
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.placeholder
                color: root.theme.cardDim
                font.family: input.font.family
                font.pixelSize: input.font.pixelSize
            }
        }
        FadeBlur {
            width: parent.width
            height: parent.height
            blurMax: root.cfg.textBlurMax
            shown: !root.locked && root.busy && input.text.length === 0
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Checking…")
                color: root.theme.cardDim
                font.family: input.font.family
                font.pixelSize: input.font.pixelSize
            }
        }
        FadeBlur {
            width: parent.width
            height: parent.height
            blurMax: root.cfg.textBlurMax
            shown: root.locked
            Row {
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.lockPrefix
                    color: root.theme.islandFg
                    font.family: input.font.family
                    font.pixelSize: input.font.pixelSize
                    font.weight: Font.DemiBold
                }
                RollingText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.lockValue
                    color: root.theme.islandFg
                    family: input.font.family
                    pixelSize: input.font.pixelSize
                    weight: Font.DemiBold
                }
            }
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
