import QtQuick

// On-screen annotation layer: one interactive AnnotationItem per model row
// (text objects edit in place) + the text-commit plumbing.
Item {
    id: root
    required property var editor
    required property Item effectSource

    readonly property var model: root.editor.model

    function commitEditingText(): void {
        const i = root.model.editingObj;
        if (i < 0)
            return;
        const item = rep.itemAt(i);
        if (item)
            item.commitNow();
        else
            root.model.editingObj = -1;
    }

    function commitText(index: int, text: string): void {
        const m = root.model;
        if (index < 0 || index >= m.objects.count)
            return;
        m.editingObj = -1;
        if (text.trim() === "") {
            m.objects.remove(index);
        } else {
            m.objects.setProperty(index, "textStr", text);
            m.objects.setProperty(index, "editing", false);
            if (m.preState !== null)
                m.pushUndo(m.preState);
        }
        m.preState = null;
        root.editor.keyTarget.forceActiveFocus();
    }

    Repeater {
        id: rep
        model: root.model.objects

        AnnotationItem {
            effectSource: root.effectSource
            pixelateFactor: root.editor.cfg.pixelateFactor
            blurMax: root.editor.cfg.effectBlurMax
            counterDiameter: root.model.counterDiameter(thickness)
            fontFamily: root.editor.theme.fontFamily
            interactive: true
            onEditCommit: (i, t) => root.commitText(i, t)
        }
    }
}
