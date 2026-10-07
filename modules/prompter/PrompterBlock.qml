import QtQuick
import "PrompterParse.js" as Parse

// One markdown block of the script: a read-only rich-text TextEdit (not
// Text: positionToRectangle gives the cursor word's line for the scroll).
// `enabled: false` keeps it press-transparent (swipe-up close lives under
// the module). Only the block holding the cursor rebuilds its HTML:
// `localCursor` is clamped to the block, so moving inside another block
// leaves this binding's value — and the rich text — untouched.
TextEdit {
    id: root

    property var block: null
    property int cursor: 0
    property var colors: ({})
    property var cfg: null
    property string family: ""

    readonly property int localCursor: !root.block ? 0
        : Math.max(root.block.first - 1, Math.min(root.block.first + root.block.count, root.cursor))
    readonly property real scale: {
        const k = root.block?.kind ?? "p";
        if (k === "h") {
            const s = root.cfg?.headingScale ?? [1.45, 1.25, 1.1];
            return s[Math.min(s.length - 1, (root.block.level ?? 1) - 1)] ?? 1;
        }
        if (k === "note")
            return root.cfg?.noteScale ?? 0.78;
        if (k === "code")
            return root.cfg?.codeScale ?? 0.72;
        return 1;
    }

    readOnly: true
    enabled: false
    selectByMouse: false
    activeFocusOnPress: false
    textFormat: TextEdit.RichText
    wrapMode: TextEdit.Wrap
    color: root.colors.ahead ?? "white"
    font.family: (root.block?.kind ?? "") === "code" ? (root.colors.mono ?? "monospace") : root.family
    font.pixelSize: Math.round((root.cfg?.fontSize ?? 28) * root.scale)
    font.weight: (root.block?.kind ?? "") === "h" ? Font.Bold : Font.Medium
    text: !root.block ? "" : `<p style="margin:0; line-height:${Math.round((root.cfg?.lineHeight ?? 1.18) * 100)}%">${Parse.htmlFor(root.block, root.localCursor, root.colors)}</p>`

    // Rect of word `w` (doc index) in this item's coordinates.
    function wordRect(w: int): rect {
        return root.positionToRectangle(Parse.charOffset(root.block, w));
    }
}
