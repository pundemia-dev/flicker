import QtQuick
import "../../components"
import "../../config"

// Translation panel (DeepL extension popup) on the selection overlay:
// grows out of the pill capsule it was opened from (capture ColorPanel /
// pShell: `growT` 0→1 on a spring, the box lerps pill rect → panel incl.
// capsule → panel radius and pill colour → island black, content scaled to
// the width fades in), closes back into that spot fading. Sits under the
// selection anchor (above it when there is no room), clamped to the screen.
// Header: source ⇄ target language chips, engine chip, copy, close; then
// the selected text (dim, 3 lines, a click shows all) and the translation.
// A chip opens its picker in place of the texts. Keys (the panel holds the
// keyboard while open): Esc = picker / panel closes, Ctrl+C = copy (the
// translation unless part of it is selected), Ctrl+Enter = replace.
Item {
    id: root
    required property var translator
    required property var theme
    property bool open: false
    // Screen-local box the panel grows out of ({x, y, w, h, color}), null =
    // a dot at the anchor.
    property var growFrom: null
    property color fromColor: root.theme.islandBg

    readonly property var cfg: root.translator.cfg.panel ?? ({})
    readonly property var job: root.translator.job
    readonly property var anchorBox: root.translator.anchor ?? { x: root.width / 2, y: root.height / 3, width: 0, height: 0 }

    readonly property real pad: root.cfg.padding ?? 14
    readonly property real gap: root.cfg.gap ?? 10
    readonly property real edge: root.cfg.edgeMargin ?? 8
    readonly property real panelW: Math.min(root.cfg.width ?? 420, root.width - 2 * root.edge)
    readonly property real maxH: Math.min(root.cfg.maxHeight ?? 420, root.height - 2 * root.edge)
    readonly property real innerW: root.panelW - 2 * root.pad

    // "" | "source" | "target" | "engine"
    property string picker: ""
    property bool sourceExpanded: false
    onOpenChanged: {
        if (root.open) {
            root.picker = "";
            root.sourceExpanded = false;
            root.start();
        } else {
            grow.enabled = true;
            root.growT = 0;
        }
    }

    // Content heights (unscaled): header + source + translation + note.
    readonly property real headerH: 28
    // Expanded: at most sourceMaxShare of the panel (the rest is the translation).
    readonly property real sourceH: Math.min(Math.ceil(srcMeasure.implicitHeight), root.maxH * (root.cfg.sourceMaxShare ?? 0.4))
    readonly property real noteH: note.visible ? note.implicitHeight + root.gap / 2 : 0
    readonly property real bodyMax: root.maxH - 2 * root.pad - root.headerH - root.gap * 2 - root.sourceH - root.noteH
    readonly property real bodyH: root.picker !== ""
        ? Math.min(langPicker.contentHeight, root.maxH - 2 * root.pad - root.headerH - root.gap)
        : Math.max(trText.fontSize * 1.4, Math.min(trText.contentHeight, root.bodyMax))
    readonly property real panelH: root.picker !== ""
        ? 2 * root.pad + root.headerH + root.gap + root.bodyH
        : 2 * root.pad + root.headerH + root.gap + root.sourceH + root.gap + root.bodyH + root.noteH
    property real panelHAnimated: root.panelH
    Behavior on panelHAnimated { id: heightSpring; Spring {} }

    // Placement (target values; growT carries the box there).
    readonly property real panelX: Math.max(root.edge, Math.min(root.width - root.edge - root.panelW,
        root.anchorBox.x + root.anchorBox.width / 2 - root.panelW / 2))
    readonly property real below: root.anchorBox.y + root.anchorBox.height + (root.cfg.anchorGap ?? 8)
    readonly property real panelY: {
        const h = root.panelHAnimated;
        const y = root.below + h + root.edge <= root.height ? root.below : root.anchorBox.y - (root.cfg.anchorGap ?? 8) - h;
        return Math.max(root.edge, Math.min(root.height - root.edge - h, y));
    }

    property real growT: 0
    property var fromRect: ({ x: 0, y: 0, w: 1, h: 1 })
    Behavior on growT { id: grow; Spring { eps: 0.002 } }
    readonly property real vx: root.fromRect.x + (root.panelX - root.fromRect.x) * root.growT
    readonly property real vy: root.fromRect.y + (root.panelY - root.fromRect.y) * root.growT
    readonly property real vw: Math.max(1, root.fromRect.w + (root.panelW - root.fromRect.w) * root.growT)
    readonly property real vh: Math.max(1, root.fromRect.h + (root.panelHAnimated - root.fromRect.h) * root.growT)

    function start(): void {
        const g = root.growFrom;
        root.fromRect = g ? { x: g.x, y: g.y, w: g.w, h: g.h }
            : { x: root.anchorBox.x - 12, y: root.below, w: 24, h: 24 };
        root.fromColor = g?.color ?? root.theme.islandBg;
        grow.enabled = heightSpring.enabled = false;
        root.growT = 0;
        // Snap to the current height, keeping the binding (a plain
        // assignment froze it at the "Translating…" line).
        root.panelHAnimated = Qt.binding(() => root.panelH);
        grow.enabled = heightSpring.enabled = true;
        root.growT = 1;
        keys.forceActiveFocus();
    }

    readonly property bool shownNow: root.open || root.growT > 0.02
    visible: root.shownNow
    opacity: root.open ? 1 : Math.min(1, root.growT * 1.6)

    function copyNow(): void {
        const t = trText.selectedText !== "" ? trText.selectedText : root.job.result;
        root.translator.copy(t);
        copied.restart();
    }
    Timer {
        id: copied
        interval: 1200
    }

    Item {
        id: keys
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) {
                if (root.picker !== "")
                    root.picker = "";
                else
                    root.translator.closePanel();
                e.accepted = true;
            } else if (e.key === Qt.Key_C && (e.modifiers & Qt.ControlModifier)) {
                root.copyNow();
                e.accepted = true;
            } else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && (e.modifiers & Qt.ControlModifier) && root.translator.editable) {
                root.translator.replace(root.job.result);
                e.accepted = true;
            }
        }
    }

    Rectangle {
        id: box
        x: root.vx
        y: root.vy
        width: root.vw
        height: root.vh
        // Pill capsule → panel corners, pill colour → island black.
        radius: root.fromRect.h / 2 + ((root.cfg.radius ?? 22) - root.fromRect.h / 2) * Math.min(1, root.growT)
        color: Qt.tint(root.fromColor, Qt.rgba(root.theme.islandBg.r, root.theme.islandBg.g, root.theme.islandBg.b, Math.min(1, root.growT * 1.4)))
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08 * root.growT)
        clip: root.growT < 0.999 || root.panelHAnimated < root.panelH - 0.5
        transform: VelocityDeform {
            item: box
            sizeW: root.panelW
            sizeH: root.panelH
        }

        // No clicks through to the outside catcher.
        MouseArea {
            anchors.fill: parent
            onPressed: keys.forceActiveFocus()
        }

        Item {
            id: content
            x: root.pad * scale
            y: root.pad * scale
            width: root.innerW
            height: root.panelH - 2 * root.pad
            scale: root.vw / root.panelW
            transformOrigin: Item.TopLeft
            opacity: Math.min(1, Math.max(0, root.growT * 2 - 0.4))

            // ── Header ──
            Row {
                id: langs
                height: root.headerH
                spacing: 4
                LangChip {
                    anchors.verticalCenter: parent.verticalCenter
                    theme: root.theme
                    chevron: true
                    checked: root.picker === "source"
                    text: root.translator.source === "auto"
                        ? (root.job.detected !== "" ? root.translator.languageName(root.job.detected) : I18n.tr("Auto"))
                        : root.translator.languageName(root.translator.source)
                    onClicked: root.picker = root.picker === "source" ? "" : "source"
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    theme: root.theme
                    width: 26
                    height: 26
                    glow: false
                    bg: "transparent"
                    glyph: "" // tabler arrows-exchange
                    iconSize: 15
                    onClicked: root.translator.swapLanguages(root.job.detected)
                }
                LangChip {
                    anchors.verticalCenter: parent.verticalCenter
                    theme: root.theme
                    chevron: true
                    checked: root.picker === "target"
                    text: root.translator.languageName(root.job.effectiveTarget || root.translator.target)
                    onClicked: root.picker = root.picker === "target" ? "" : "target"
                }
            }
            Row {
                anchors.right: parent.right
                height: root.headerH
                spacing: 4
                LangChip {
                    anchors.verticalCenter: parent.verticalCenter
                    theme: root.theme
                    subtle: true
                    chevron: true
                    checked: root.picker === "engine"
                    text: root.translator.engineName(root.translator.engine)
                    fontSize: root.theme.fontSizeIndicator
                    onClicked: root.picker = root.picker === "engine" ? "" : "engine"
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    theme: root.theme
                    width: 26
                    height: 26
                    glow: false
                    visible: root.translator.editable
                    disabled: root.job.result === "" || root.job.busy
                    glyph: "" // tabler replace
                    iconSize: 14
                    onClicked: root.translator.replace(root.job.result)
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    theme: root.theme
                    width: 26
                    height: 26
                    glow: false
                    disabled: root.job.result === ""
                    glyph: copied.running ? "" : "" // tabler check / copy
                    iconSize: 14
                    onClicked: root.copyNow()
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    theme: root.theme
                    width: 26
                    height: 26
                    glow: false
                    glyph: "" // tabler x
                    iconSize: 14
                    onClicked: root.translator.closePanel()
                }
            }

            // ── Texts ──
            FadeBlur {
                id: texts
                y: root.headerH + root.gap
                width: parent.width
                height: parent.height - y
                shown: root.picker === ""

                // Unsized twin = the height (see TranslationText).
                Text {
                    id: srcMeasure
                    visible: false
                    width: parent.width
                    text: srcText.text
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    maximumLineCount: srcText.maximumLineCount
                    font: srcText.font
                }
                Text {
                    id: srcText
                    width: parent.width
                    height: root.sourceH
                    clip: true
                    text: root.translator.text
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    elide: root.sourceExpanded ? Text.ElideNone : Text.ElideRight
                    maximumLineCount: root.sourceExpanded ? 1000 : (root.cfg.sourceLines ?? 3)
                    color: root.theme.subtleFg
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.cfg.sourceSize ?? 12
                    renderType: Text.QtRendering
                    MouseArea {
                        anchors.fill: parent
                        enabled: srcMeasure.truncated || root.sourceExpanded
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.sourceExpanded = !root.sourceExpanded
                    }
                }

                Rectangle {
                    id: rule
                    y: srcText.height + root.gap / 2
                    width: parent.width
                    height: 1
                    color: root.theme.launcherDivider
                }

                TranslationText {
                    id: trText
                    y: srcText.height + root.gap
                    width: parent.width
                    height: root.bodyH
                    theme: root.theme
                    fontSize: root.cfg.fontSize ?? 15
                    text: root.job.result
                    busy: root.job.busy
                    error: root.job.error
                }

                // DeepL: the text was already in the target language.
                Text {
                    id: note
                    y: trText.y + trText.height + root.gap / 2
                    width: parent.width
                    visible: root.job.effectiveTarget !== root.translator.target && root.job.result !== ""
                    wrapMode: Text.Wrap
                    text: I18n.tr("Already in %1 — translated to %2")
                        .arg(root.translator.languageName(root.translator.target))
                        .arg(root.translator.languageName(root.job.effectiveTarget))
                    color: root.theme.subtleFg
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fontSizeTiny
                    renderType: Text.QtRendering
                }
            }

            // ── Picker (in place of the texts) ──
            FadeBlur {
                y: root.headerH + root.gap
                width: parent.width
                height: root.bodyH
                shown: root.picker !== ""

                LanguagePicker {
                    id: langPicker
                    anchors.fill: parent
                    theme: root.theme
                    readonly property string kind: root.picker !== "" ? root.picker : langPicker.lastKind
                    property string lastKind: "target"
                    onKindChanged: if (root.picker !== "") langPicker.lastKind = root.picker
                    options: langPicker.kind === "engine" ? root.translator.engines
                        : (langPicker.kind === "source" ? root.translator.languages : root.translator.targets)
                            .map(l => ({ id: l.code, name: root.translator.languageName(l.code) }))
                    current: langPicker.kind === "engine" ? root.translator.engine
                        : (langPicker.kind === "source" ? root.translator.source : root.translator.target)
                    onPicked: id => {
                        if (langPicker.kind === "engine")
                            root.translator.setEngine(id);
                        else if (langPicker.kind === "source")
                            root.translator.setSource(id);
                        else
                            root.translator.setTarget(id);
                        root.picker = "";
                    }
                }
            }
        }
    }
}
