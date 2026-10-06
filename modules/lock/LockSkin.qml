import QtQuick
import Quickshell
import "../../components"
import "../../config"

// Minimal lock skin: dark bg, clock, password dots, state feedback.
// Receives lock/pam/screen as initial properties (see LockSurface).
Item {
    id: root

    required property var lock
    required property var pam
    required property ShellScreen screen

    focus: true

    Keys.onPressed: event => {
        pam.handleKey(event);
        event.accepted = true;
    }

    Rectangle {
        anchors.fill: parent
        color: "#0D0E11"

        // Fail/error flash + shake feedback
        Rectangle {
            id: flash
            anchors.fill: parent
            color: "#B33"
            opacity: 0
            SequentialAnimation {
                id: flashAnim
                NumberAnimation { target: flash; property: "opacity"; to: 0.22; duration: 90 }
                NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 260 }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 14

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(new Date(), "HH:mm")
                color: "#EDF1F8"
                font.pixelSize: 64
                font.weight: Font.Light
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.capitalize(new Date().toLocaleDateString(I18n.locale, I18n.tr("dddd, MMMM d")))
                color: "#8B93A3"
                font.pixelSize: 15
            }

            Row {
                id: dots
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                Repeater {
                    model: Math.min(root.pam.buffer.length, 16)
                    Rectangle {
                        width: 9
                        height: 9
                        radius: 4.5
                        color: "#C7D0DE"
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: text.length > 0
                text: {
                    if (root.pam.state === "fail")
                        return I18n.tr("Incorrect password");
                    if (root.pam.state === "error")
                        return I18n.tr("Authentication error");
                    if (root.pam.state === "max")
                        return I18n.tr("Too many attempts");
                    return root.pam.lockMessage;
                }
                color: "#D98080"
                font.pixelSize: 12
            }
        }
    }

    Connections {
        target: root.pam
        function onFlashMsg(): void {
            flashAnim.restart();
            shakeAnim.restart();
        }
    }

    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: dots; property: "anchors.horizontalCenterOffset"; to: -10; duration: 50 }
        NumberAnimation { target: dots; property: "anchors.horizontalCenterOffset"; to: 10; duration: 70 }
        NumberAnimation { target: dots; property: "anchors.horizontalCenterOffset"; to: 0; duration: 50 }
    }

    Connections {
        target: root.lock
        function onUnlock(): void {
            exitAnim.start();
        }
    }

    // Blur→fade style exit: content fades, then surface releases.
    SequentialAnimation {
        id: exitAnim
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: 220 }
        ScriptAction { script: root.lock.finishUnlock() }
    }
}
