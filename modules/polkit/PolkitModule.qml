import QtQuick
import "../../components"

// Polkit prompt as an island module (services/Polkit is the agent). Layout:
// lock disc + title / message, the pkexec command on its own monospace
// plate, identity (tap to cycle when polkit offers several admins), password
// pill, status line (wrong password / PAM info such as a fingerprint
// prompt), Отмена / Подтвердить. Success swaps the lock for a green tick
// before Island closes the module (`polkit.successHoldMs`).
// Height is content-fitted: preferredHeight → ModuleHost → Island.moduleSize.
Item {
    id: root
    required property var polkit
    required property var theme
    required property var cfg
    signal closeRequested

    readonly property var req: root.polkit.request
    readonly property bool success: root.polkit.phase === "success"
    readonly property bool busy: root.polkit.phase === "checking" || root.success
    readonly property real preferredWidth: root.cfg.width
    readonly property real preferredHeight: body.implicitHeight + root.cfg.padding * 2

    function confirm(): void {
        root.polkit.submit(field.text);
        field.clear();
    }

    Connections {
        target: root.polkit
        function onFailCountChanged(): void {
            if (root.polkit.failCount > 0)
                field.shake();
        }
        function onPhaseChanged(): void {
            if (root.polkit.phase === "input")
                field.focusField();
            else if (root.polkit.phase === "success")
                bump.bump();
        }
    }

    GlyphBump { id: bump }

    Column {
        id: body
        x: root.cfg.padding
        y: root.cfg.padding
        width: root.width - root.cfg.padding * 2
        spacing: root.cfg.gap

        // ── Header ──
        Item {
            width: parent.width
            height: Math.max(disc.height, headText.implicitHeight)

            Rectangle {
                id: disc
                width: root.cfg.discSize
                height: width
                radius: width / 2
                color: root.theme.cardBg

                Text {
                    anchors.centerIn: parent
                    text: "" // tabler lock
                    font.family: root.theme.iconFamily
                    font.pixelSize: root.cfg.iconSize
                    color: root.theme.islandFg
                    opacity: root.success ? 0 : 1
                    Behavior on opacity { Spring { eps: 0.01 } }
                }
                Text {
                    anchors.centerIn: parent
                    text: "" // tabler circle-check-filled
                    font.family: root.theme.iconFamily
                    font.pixelSize: root.cfg.iconSize
                    color: root.theme.accentGreen
                    opacity: root.success ? 1 : 0
                    scale: bump.value
                    Behavior on opacity { Spring { eps: 0.01 } }
                }
            }

            Column {
                id: headText
                anchors.left: disc.right
                anchors.leftMargin: root.cfg.gap
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    width: parent.width
                    text: root.success ? "Доступ разрешён" : (root.req?.title ?? "")
                    color: root.theme.islandFg
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.cfg.titleSize
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: root.req?.message ?? ""
                    color: root.theme.subtleFg
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.cfg.fontSize
                    wrapMode: Text.Wrap
                    maximumLineCount: root.cfg.messageLines
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }
        }

        // ── pkexec command ──
        Rectangle {
            visible: (root.req?.command ?? "") !== ""
            width: parent.width
            height: cmdText.implicitHeight + root.cfg.gap * 1.5
            radius: Math.min(height / 2, root.cfg.fieldHeight / 2)
            color: root.theme.cardBg

            Text {
                id: cmdText
                anchors.verticalCenter: parent.verticalCenter
                x: parent.radius
                width: parent.width - parent.radius * 2
                text: root.req?.command ?? ""
                color: root.theme.islandFg
                font.family: root.cfg.monoFamily
                font.pixelSize: root.cfg.fontSize
                wrapMode: Text.WrapAnywhere
                maximumLineCount: root.cfg.commandLines
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
        }

        // ── Identity ──
        Item {
            visible: root.polkit.identityName !== ""
            width: idRow.implicitWidth
            height: idRow.implicitHeight
            opacity: identityMa.containsMouse ? 1 : 0.8

            Row {
                id: idRow
                spacing: root.cfg.gap / 2

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\ueb4d" // tabler user
                    font.family: root.theme.iconFamily
                    font.pixelSize: root.cfg.fontSize + 2
                    color: root.theme.cardDim
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.polkit.identityName
                    color: root.theme.subtleFg
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.cfg.fontSize
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.polkit.identities.length > 1
                    text: "\ueb1d" // tabler selector
                    font.family: root.theme.iconFamily
                    font.pixelSize: root.cfg.fontSize + 2
                    color: root.theme.cardDim
                }
            }

            MouseArea {
                id: identityMa
                anchors.fill: parent
                hoverEnabled: true
                enabled: root.polkit.identities.length > 1 && !root.busy
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.polkit.nextIdentity()
            }
        }

        // ── Password ──
        PolkitField {
            id: field
            width: parent.width
            theme: root.theme
            cfg: root.cfg
            placeholder: root.polkit.prompt !== "" && !/^пароль$|^password$/i.test(root.polkit.prompt)
                ? root.polkit.prompt : "Пароль"
            plainText: root.polkit.responseVisible
            busy: root.busy
            error: root.polkit.failCount > 0 && root.polkit.phase === "input"
            onAccepted: root.confirm()
            onEscaped: root.polkit.cancel()
            Component.onCompleted: focusField()
        }

        // ── Status ──
        Text {
            readonly property string msg: root.polkit.supplementary !== "" ? root.polkit.supplementary
                : root.polkit.failCount > 0 && !root.busy ? "Неверный пароль, попробуйте ещё раз" : ""
            readonly property bool isError: root.polkit.supplementary !== "" ? root.polkit.supplementaryIsError : true
            visible: msg !== ""
            width: parent.width
            text: msg
            color: isError ? root.theme.accentRed : root.theme.subtleFg
            font.family: root.theme.fontFamily
            font.pixelSize: root.cfg.fontSize
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }

        // ── Actions ──
        Row {
            anchors.right: parent.right
            spacing: root.cfg.gap

            PolkitButton {
                theme: root.theme
                cfg: root.cfg
                label: "Отмена"
                enabled: !root.success
                onClicked: root.polkit.cancel()
            }
            PolkitButton {
                theme: root.theme
                cfg: root.cfg
                label: "Подтвердить"
                base: root.theme.qsBlue
                enabled: !root.busy && field.text.length > 0
                onClicked: root.confirm()
            }
        }
    }
}
