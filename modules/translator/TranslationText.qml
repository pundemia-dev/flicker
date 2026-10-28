import QtQuick
import "../../components"
import "../../config"

// The translation itself: selectable read-only text that wheel-scrolls
// when longer than its box (no Flickable: a drag selects). While a request
// runs with nothing yet a dimmed "Translating…" stands in its place; an
// error shows in red. `contentHeight` = the full text height (the panel /
// launcher body size themselves from it).
Item {
    id: root
    required property var theme
    property string text: ""
    property bool busy: false
    property string error: ""
    property real fontSize: 15
    property alias selectedText: edit.selectedText

    readonly property bool showing: root.text !== ""
    // Measured on unsized twins: an item whose height is bound to a size
    // derived from its own implicit height can collapse to one line.
    readonly property real contentHeight: Math.ceil(root.showing ? twin.implicitHeight : status.implicitHeight) + 2
    clip: true

    readonly property real maxScroll: Math.max(0, root.contentHeight - root.height)
    property real scroll: 0
    onTextChanged: if (root.scroll > root.maxScroll) root.scroll = root.maxScroll

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 2;
            root.scroll = Math.max(0, Math.min(root.maxScroll, root.scroll - delta));
        }
    }

    TextEdit {
        id: edit
        width: root.width
        property real scrollY: root.scroll
        Behavior on scrollY { Spring { stiffness: 6; damp: 0.6 } }
        y: -scrollY
        visible: root.showing
        readOnly: true
        selectByMouse: true
        persistentSelection: true
        wrapMode: TextEdit.Wrap
        textFormat: TextEdit.PlainText
        text: root.text
        color: root.theme.islandFg
        selectionColor: root.theme.cardBlue
        selectedTextColor: root.theme.islandFg
        font.family: root.theme.fontFamily
        font.pixelSize: root.fontSize
        // Native text on a transparent layer surface fringes (KeyboardPill).
        renderType: TextEdit.QtRendering
    }

    Text {
        id: twin
        visible: false
        width: root.width
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: root.text
        font: edit.font
    }

    Text {
        id: status
        width: root.width
        visible: !root.showing
        wrapMode: Text.Wrap
        text: root.error !== "" ? root.error : (root.busy ? I18n.tr("Translating…") : "")
        color: root.error !== "" ? root.theme.accentRed : root.theme.subtleFg
        font.family: root.theme.fontFamily
        font.pixelSize: root.error !== "" ? root.theme.fontSizeBody : root.fontSize
        renderType: Text.QtRendering
    }
}
