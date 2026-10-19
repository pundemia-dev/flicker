import QtQuick
import "../../components"
import "../../config"

// Inline text value (iOS: right-aligned grey text you click into). Commits
// on Enter or when focus leaves (a click elsewhere); Esc restores the stored
// text and leaves; an emptied field restores it too, unless `allowEmpty`.
Item {
    id: root
    required property var theme
    property string text: ""
    property string placeholder: ""
    property int align: TextInput.AlignRight
    property bool allowEmpty: false
    signal committed(string text)

    implicitHeight: input.implicitHeight

    TextInput {
        id: input
        anchors.fill: parent
        horizontalAlignment: root.align
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        selectByMouse: true
        color: activeFocus ? root.theme.islandFg : root.theme.settingsSecondary
        selectionColor: root.theme.qsBlue
        font.family: root.theme.fontFamily
        font.pixelSize: 15
        // Follows the stored value while not being edited. RestoreNone: the
        // default restore put back the field's initial "" on focus, so a
        // click into the field emptied it.
        Binding on text {
            when: !input.activeFocus
            value: root.text
            restoreMode: Binding.RestoreNone
        }
        onAccepted: focus = false
        // Leaving the field commits; left empty, the stored value comes back.
        onActiveFocusChanged: {
            if (activeFocus)
                return;
            if (text.trim() === "" && !root.allowEmpty)
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
        horizontalAlignment: root.align
        text: I18n.tr(root.placeholder || "Not set")
        color: root.theme.settingsSecondary
        opacity: 0.6
        font.family: root.theme.fontFamily
        font.pixelSize: 15
    }
}
