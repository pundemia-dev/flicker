import QtQuick
import "../../components"

// Search row (pShell RowInput port): magnifier that grows into the active
// plugin's name tag (blue; red while a second Backspace would leave the
// plugin), text field, clear ✕ and the plugin's optional extension button.
// Keys go to the host as signals; colour changes are opacity-spring
// crossfades of stacked layers (no timed colour tweens).
Rectangle {
    id: root
    required property var manager
    required property var theme
    required property var cfg

    signal moveUp
    signal moveDown
    signal execute(string query, bool isAlt)
    signal closeRequested

    readonly property bool tagShown: root.manager.currentState === root.manager.stateActive
    readonly property bool tagError: root.manager.escapePending
    readonly property real tagH: root.height - root.cfg.inputInset * 2

    // No plate: the search row sits on the island body, a divider
    // (LauncherModule) separates it from the results.
    color: "transparent"

    function clear(): void {
        field.text = "";
    }

    function setText(t: string): void {
        field.text = t;
        field.forceActiveFocus();
        field.cursorPosition = field.text.length;
    }

    function focusField(): void {
        field.forceActiveFocus();
    }

    Connections {
        target: root.manager
        function onPluginActivated(): void {
            field.text = "";
            field.forceActiveFocus();
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onClicked: field.forceActiveFocus()
    }

    // Magnifier disc → plugin tag.
    Item {
        id: tag
        x: root.cfg.inputInset
        anchors.verticalCenter: parent.verticalCenter
        height: root.tagH
        width: root.tagShown ? tagRow.implicitWidth + root.tagH / 2 : root.tagH
        Behavior on width { Spring { stiffness: 5; damp: 0.4; eps: 0.25 } }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.theme.qsBlue
            opacity: root.tagShown && !root.tagError ? 1 : 0
            Behavior on opacity { Spring { eps: 0.01 } }
        }
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.theme.accentRed
            opacity: root.tagShown && root.tagError ? 1 : 0
            Behavior on opacity { Spring { eps: 0.01 } }
        }

        Item {
            anchors.fill: parent
            clip: true

            Row {
                id: tagRow
                height: parent.height

                Text {
                    width: root.tagH
                    height: parent.height
                    horizontalAlignment: Text.AlignHCenter
                    text: "" // tabler search
                    font.family: root.theme.iconFamily
                    font.pixelSize: root.cfg.iconSize
                    color: root.theme.islandFg
                }
                Text {
                    height: parent.height
                    text: root.manager.activeManifest?.title ?? ""
                    font.pixelSize: root.cfg.fontSize
                    font.weight: Font.DemiBold
                    color: root.theme.islandFg
                    opacity: root.tagShown ? 1 : 0
                    Behavior on opacity { Spring { eps: 0.01 } }
                }
            }
        }
    }

    TextInput {
        id: field
        anchors.left: tag.right
        anchors.leftMargin: root.cfg.itemPadding
        anchors.right: clearBtn.left
        anchors.rightMargin: root.cfg.inputInset
        anchors.verticalCenter: parent.verticalCenter
        color: root.theme.islandFg
        selectionColor: root.theme.qsBlue
        selectedTextColor: root.theme.islandFg
        font.family: root.theme.fontFamily
        font.pixelSize: root.cfg.fontSize
        clip: true
        focus: true

        onTextEdited: root.manager.processInput(text)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.tagShown ? "Поиск" : `Поиск · «${root.manager.magicSymbol}» — модули`
            color: root.theme.cardDim
            font.pixelSize: root.cfg.fontSize
            visible: field.text.length === 0
        }

        Keys.onPressed: event => {
            if (event.key !== Qt.Key_Backspace || text.length > 0)
                root.manager.cancelEscape();
            switch (event.key) {
            case Qt.Key_Backspace:
                if (text.length === 0) {
                    const t = root.manager.handleBackspaceOnEmpty(event.isAutoRepeat);
                    if (t !== null)
                        root.setText(t);
                    event.accepted = true;
                }
                break;
            case Qt.Key_Up:
                root.moveUp();
                event.accepted = true;
                break;
            case Qt.Key_Down:
            case Qt.Key_Tab:
                root.moveDown();
                event.accepted = true;
                break;
            case Qt.Key_Backtab:
                root.moveUp();
                event.accepted = true;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                root.execute(text, (event.modifiers & Qt.AltModifier) !== 0);
                event.accepted = true;
                break;
            case Qt.Key_Escape:
                root.closeRequested();
                event.accepted = true;
                break;
            }
        }

        Component.onCompleted: forceActiveFocus()
    }

    // Clear ✕ (collapses while the field is empty).
    Text {
        id: clearBtn
        anchors.right: ext.left
        anchors.rightMargin: field.text.length > 0 ? root.cfg.inputInset : 0
        anchors.verticalCenter: parent.verticalCenter
        width: field.text.length > 0 ? root.tagH * 0.6 : 0
        horizontalAlignment: Text.AlignHCenter
        text: "" // tabler x
        font.family: root.theme.iconFamily
        font.pixelSize: root.cfg.iconSize - 2
        color: root.theme.cardDim
        opacity: field.text.length === 0 ? 0 : (clearMa.containsMouse ? 1 : 0.7)
        Behavior on opacity { Spring { eps: 0.01 } }
        Behavior on width { Spring { eps: 0.25 } }

        MouseArea {
            id: clearMa
            anchors.fill: parent
            hoverEnabled: true
            enabled: field.text.length > 0
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                field.text = "";
                root.manager.processInput("");
                field.forceActiveFocus();
            }
        }
    }

    // Plugin extension (e.g. the apps details toggle).
    Loader {
        id: ext
        anchors.right: parent.right
        anchors.rightMargin: root.cfg.inputInset
        anchors.verticalCenter: parent.verticalCenter
        height: root.tagH
        width: item ? root.tagH : 0
        sourceComponent: root.manager.currentState === root.manager.stateSelecting
            ? null : (root.manager.activePlugin?.inputExtensionComponent ?? null)
    }
}
