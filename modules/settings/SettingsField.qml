import QtQuick
import "../../components"
import "../../config"

// Inline text value (iOS: right-aligned grey text you click into). Commits
// on Enter or when focus leaves (a click elsewhere); Esc restores the stored
// text and leaves; an emptied field restores it too.
Item {
    id: root
    required property var theme
    property string text: ""
    signal committed(string text)

    implicitHeight: input.implicitHeight

    TextInput {
        id: input
        anchors.fill: parent
        horizontalAlignment: TextInput.AlignRight
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        selectByMouse: true
        color: activeFocus ? root.theme.islandFg : root.theme.settingsSecondary
        selectionColor: root.theme.qsBlue
        font.family: root.theme.fontFamily
        font.pixelSize: 15
        // Follows the stored value while not being edited.
        Binding on text {
            when: !input.activeFocus
            value: root.text
        }
        onAccepted: focus = false
        // Leaving the field commits; left empty, the stored value comes back.
        onActiveFocusChanged: {
            if (activeFocus)
                return;
            if (text.trim() === "")
                text = root.text;
            else if (text !== root.text)
                root.committed(text);
        }
        Keys.onEscapePressed: event => {
            text = root.text;
            focus = false;
            event.accepted = true;
        }
    }

    Text {
        anchors.fill: parent
        visible: input.text === "" && !input.activeFocus
        horizontalAlignment: Text.AlignRight
        text: I18n.tr("Not set")
        color: root.theme.settingsSecondary
        opacity: 0.6
        font.family: root.theme.fontFamily
        font.pixelSize: 15
    }
}
