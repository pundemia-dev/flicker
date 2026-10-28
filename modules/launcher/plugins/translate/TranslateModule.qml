import QtQuick
import Quickshell
import "../../api"
import "../../../../components"
import "../../../../config"
import "../../../../services"
import "../../../translator"

// Translator in the launcher (`!tr`): the search field is the source text,
// the body below shows the translation (services/TranslateJob, the same
// engines / languages as the selection panel — services/Translator via
// LauncherPlugin.host.translator). Requests go out translator.debounceMs
// after the last keystroke; the previous translation stays until the new
// one lands. Keys: Enter = copy + close, Alt+Enter = the translation
// becomes the input (languages swap), Tab = target ⇄ translator.secondTarget.
// The body height follows the text (translator.launcher.minHeight..maxHeight).
LauncherPlugin {
    id: root

    readonly property var translator: root.host?.translator ?? null
    readonly property var tcfg: root.translator?.cfg ?? ({})
    readonly property var lcfg: root.tcfg.launcher ?? ({})
    readonly property var job: jobLoader.item
    property string query: ""
    // "" | "source" | "target" | "engine"
    property string picker: ""

    // No rows: the body is the whole UI.
    ScriptModel {
        id: noRows
        values: []
    }
    listModel: noRows
    bodyComponent: bodyComp
    bodyWidth: root.cfg?.width ?? 560
    readonly property real headerH: 28
    readonly property real gap: 10
    readonly property real footerH: 18
    readonly property real textH: root.picker !== "" ? pickerMeasure.implicitHeight
        : Math.max(measure.implicitHeight, (root.lcfg.fontSize ?? 17) * 1.4)
    bodyHeight: Math.max(root.lcfg.minHeight ?? 120, Math.min(root.lcfg.maxHeight ?? 360,
        root.headerH + root.gap + root.textH + root.gap + root.footerH))

    // TranslateJob needs the service (host arrives after creation).
    Loader {
        id: jobLoader
        active: !!root.translator
        sourceComponent: TranslateJob {
            translator: root.translator
            source: root.translator.source
            target: root.translator.target
            engine: root.translator.engine
        }
    }
    readonly property string trigger: root.translator ? `${root.translator.source}|${root.translator.target}|${root.translator.engine}` : ""
    onTriggerChanged: if (root.isActive && root.query !== "") debounce.restart()

    Timer {
        id: debounce
        interval: root.tcfg.debounceMs ?? 450
        onTriggered: {
            if (!root.job)
                return;
            root.job.text = root.query;
            root.job.run();
        }
    }

    // Height of the translation at the body width (hidden twin).
    Text {
        id: measure
        visible: false
        width: root.bodyWidth
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: root.job?.result || " "
        font.family: root.theme?.fontFamily ?? "SF Pro Display"
        font.pixelSize: root.lcfg.fontSize ?? 17
    }
    Flow {
        id: pickerMeasure
        visible: false
        width: root.bodyWidth
        spacing: 6
        Repeater {
            model: root.pickerOptions
            Item {
                required property var modelData
                width: probeText.implicitWidth + 20
                height: 26
                Text {
                    id: probeText
                    text: parent.modelData.name
                    font.family: root.theme?.fontFamily ?? "SF Pro Display"
                    font.pixelSize: root.theme?.fontSizeBody ?? 12
                    font.weight: Font.DemiBold
                }
            }
        }
    }
    readonly property var pickerOptions: !root.translator ? [] : root.pickerKind === "engine" ? root.translator.engines
        : (root.pickerKind === "source" ? root.translator.languages : root.translator.targets)
            .map(l => ({ id: l.code, name: root.translator.languageName(l.code) }))
    property string pickerKind: "target"
    onPickerChanged: if (root.picker !== "") root.pickerKind = root.picker
    function pick(id: string): void {
        if (root.pickerKind === "engine")
            root.translator.setEngine(id);
        else if (root.pickerKind === "source")
            root.translator.setSource(id);
        else
            root.translator.setTarget(id);
        root.picker = "";
    }

    function onActivated(initialQuery: string): void {
        root.picker = "";
        root.handleInput(initialQuery ?? "");
    }
    function onDeactivated(): void {
        debounce.stop();
        root.job?.abort();
    }
    function handleInput(q: string): void {
        root.query = q ?? "";
        if (root.query.trim() === "") {
            debounce.stop();
            if (root.job) {
                root.job.text = "";
                root.job.run();
            }
            return;
        }
        debounce.restart();
    }

    function handleKey(event: var): bool {
        if (event.key === Qt.Key_Tab && root.translator) {
            const second = root.tcfg.secondTarget ?? "";
            const cur = root.translator.target;
            if (second !== "" && second !== cur) {
                Config.set("translator.secondTarget", cur);
                root.translator.setTarget(second);
            }
            return true;
        }
        if (event.key === Qt.Key_Escape && root.picker !== "") {
            root.picker = "";
            return true;
        }
        return false;
    }
    function handleExecute(query: string, isAlt: bool): bool {
        const out = root.job?.result ?? "";
        if (out === "")
            return true;
        if (isAlt) {
            root.translator.swapLanguages(root.job.detected);
            root.requestSetInput(out);
            root.handleInput(out);
        } else {
            root.translator.copy(out);
            root.requestClose(true);
        }
        return true;
    }

    Component {
        id: bodyComp
        Item {
            id: body

            Row {
                height: root.headerH
                spacing: 4
                LangChip {
                    anchors.verticalCenter: parent.verticalCenter
                    theme: root.theme
                    chevron: true
                    checked: root.picker === "source"
                    text: root.translator.source === "auto"
                        ? ((root.job?.detected ?? "") !== "" ? root.translator.languageName(root.job.detected) : I18n.tr("Auto"))
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
                    onClicked: root.translator.swapLanguages(root.job?.detected ?? "")
                }
                LangChip {
                    anchors.verticalCenter: parent.verticalCenter
                    theme: root.theme
                    chevron: true
                    checked: root.picker === "target"
                    text: root.translator.languageName(root.job?.effectiveTarget || root.translator.target)
                    onClicked: root.picker = root.picker === "target" ? "" : "target"
                }
            }
            LangChip {
                anchors.right: parent.right
                y: (root.headerH - height) / 2
                theme: root.theme
                subtle: true
                chevron: true
                checked: root.picker === "engine"
                text: root.translator.engineName(root.translator.engine)
                fontSize: root.theme.fontSizeIndicator
                onClicked: root.picker = root.picker === "engine" ? "" : "engine"
            }

            FadeBlur {
                y: root.headerH + root.gap
                width: parent.width
                height: parent.height - y - root.gap - root.footerH
                shown: root.picker === ""

                TranslationText {
                    anchors.fill: parent
                    theme: root.theme
                    fontSize: root.lcfg.fontSize ?? 17
                    text: root.job?.result ?? ""
                    busy: root.job?.busy ?? false
                    error: root.job?.error ?? ""
                }
                Text {
                    visible: root.query.trim() === ""
                    text: I18n.tr("Type the text to translate")
                    color: root.theme.subtleFg
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.lcfg.fontSize ?? 17
                }
            }
            FadeBlur {
                y: root.headerH + root.gap
                width: parent.width
                height: parent.height - y
                shown: root.picker !== ""
                LanguagePicker {
                    anchors.fill: parent
                    theme: root.theme
                    options: root.pickerOptions
                    current: root.pickerKind === "engine" ? root.translator.engine
                        : (root.pickerKind === "source" ? root.translator.source : root.translator.target)
                    onPicked: id => root.pick(id)
                }
            }

            Text {
                anchors.bottom: parent.bottom
                width: parent.width
                height: root.footerH
                opacity: root.picker === "" ? 1 : 0
                text: (root.job?.effectiveTarget ?? root.translator.target) !== root.translator.target && (root.job?.result ?? "") !== ""
                    ? I18n.tr("Already in %1 — translated to %2").arg(root.translator.languageName(root.translator.target)).arg(root.translator.languageName(root.job.effectiveTarget))
                    : I18n.tr("Enter — copy · Alt+Enter — translate back · Tab — %1 ⇄ %2")
                        .arg(root.translator.languageName(root.translator.target))
                        .arg(root.translator.languageName(root.tcfg.secondTarget ?? ""))
                color: root.theme.subtleFg
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fontSizeTiny
                elide: Text.ElideRight
            }
        }
    }
}
