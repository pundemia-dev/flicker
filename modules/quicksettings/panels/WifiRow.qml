import QtQuick
import "../../../components"
import "../../../config"

// One network in the Wi‑Fi panel: signal glyph, SSID (+ state line while
// joining / after a failure), lock for secured networks, check on the
// current one. The row of a new secured network grows a password field
// (Enter joins, Esc folds it).
Item {
    id: root
    required property Item panel
    required property string ssid
    required property int strength
    required property bool secure
    required property bool active
    required property bool known

    readonly property var pc: root.panel.pc
    readonly property var theme: root.panel.theme
    readonly property var net: root.panel.net
    readonly property real rowH: root.pc.rowHeight ?? 42
    readonly property real fieldH: root.pc.fieldHeight ?? 34
    readonly property bool asking: root.panel.joinSsid === root.ssid
    readonly property bool joining: root.net?.connecting === root.ssid
    readonly property bool failed: root.net?.failed === root.ssid

    property real fieldP: root.asking ? 1 : 0
    Behavior on fieldP { Spring { stiffness: 5; damp: 0.5; eps: 0.005 } }
    height: Math.round(root.rowH + root.fieldP * (root.fieldH + 8))

    onAskingChanged: {
        if (root.asking) {
            field.text = "";
            field.forceActiveFocus();
        }
    }

    // Hover / press plate.
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
        width: parent.width
        height: root.rowH
        hoverEnabled: true
        cursorShape: root.active ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: root.panel.tap({ ssid: root.ssid, secure: root.secure, active: root.active, known: root.known })
    }

    Icon {
        id: glyph
        x: root.panel.pad
        width: root.pc.glyphSize ?? 20
        height: root.rowH
        text: root.strength >= 70 ? "" : root.strength >= 45 ? "" : root.strength >= 20 ? "" : ""
        font.family: root.theme?.iconFamily ?? "tabler-icons"
        iconSize: root.pc.glyphSize ?? 20
        iconColor: "white"
    }

    Column {
        x: glyph.x + glyph.width + 12
        width: tail.x - x - 8
        y: Math.round((root.rowH - height) / 2)
        Text {
            width: parent.width
            text: root.ssid
            color: "white"
            font.pixelSize: root.pc.textSize ?? 14
            font.weight: root.active ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            visible: root.joining || root.failed
            text: root.joining ? I18n.tr("Connecting…") : I18n.tr("Couldn't connect")
            color: root.failed && !root.joining ? (root.theme?.accentRed ?? "#E4483E") : (root.theme?.cardDim ?? "#99EBEBF5")
            font.pixelSize: (root.pc.textSize ?? 14) - 3
        }
    }

    Row {
        id: tail
        anchors.right: parent.right
        anchors.rightMargin: root.panel.pad
        height: root.rowH
        spacing: 8
        Icon {
            visible: root.secure
            height: parent.height
            text: ""
            font.family: root.theme?.iconFamily ?? "tabler-icons"
            iconSize: (root.pc.glyphSize ?? 20) - 4
            iconColor: root.theme?.cardDim ?? "#99EBEBF5"
        }
        Icon {
            visible: root.active
            height: parent.height
            text: ""
            font.family: root.theme?.iconFamily ?? "tabler-icons"
            iconSize: (root.pc.glyphSize ?? 20) - 2
            iconColor: root.theme?.qsBlue ?? "#017EFC"
        }
    }

    // Password field + Join.
    FadeBlur {
        shown: root.asking
        x: root.panel.pad
        y: root.rowH
        width: parent.width - 2 * root.panel.pad
        height: root.fieldH

        Rectangle {
            id: fieldBg
            width: parent.width - join.width - 8
            height: parent.height
            radius: height / 2
            color: root.panel.frost?.layerColor(root.theme?.qsDisc ?? "#3A3A3C") ?? (root.theme?.qsDisc ?? "#3A3A3C")

            TextInput {
                id: field
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                color: "white"
                selectionColor: root.theme?.qsBlue ?? "#017EFC"
                font.pixelSize: (root.pc.textSize ?? 14) - 1
                clip: true
                enabled: root.asking
                onAccepted: join.submit()
                Keys.onEscapePressed: root.panel.joinSsid = ""

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: field.text.length === 0
                    text: I18n.tr("Password")
                    color: root.theme?.cardDim ?? "#99EBEBF5"
                    font.pixelSize: field.font.pixelSize
                }
            }
        }

        Rectangle {
            id: join
            function submit(): void {
                if (field.text.length === 0)
                    return;
                root.net?.join(root.ssid, field.text);
                root.panel.joinSsid = "";
            }
            anchors.right: parent.right
            height: parent.height
            width: joinText.implicitWidth + 28
            radius: height / 2
            color: root.theme?.qsBlue ?? "#017EFC"
            opacity: field.text.length > 0 ? 1 : 0.5
            Text {
                id: joinText
                anchors.centerIn: parent
                text: I18n.tr("Join")
                color: "white"
                font.pixelSize: (root.pc.textSize ?? 14) - 1
                font.weight: Font.DemiBold
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: join.submit()
            }
        }
    }
}
