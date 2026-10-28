import QtQuick
import "../../api"
import "../../../../config"

LauncherManifest {
    pluginId: "translate"
    title: I18n.tr("Translate")
    description: I18n.tr("Type text, get the translation (Google, DeepL, AI)")
    icon: "" // tabler language
    trigger: "tr translate"
    order: 25
    content: Component {
        TranslateModule {}
    }
}
