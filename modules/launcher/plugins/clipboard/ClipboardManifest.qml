import QtQuick
import "../../api"
import "../../../../config"

LauncherManifest {
    pluginId: "clipboard"
    title: I18n.tr("Clipboard")
    description: I18n.tr("Clipboard history (cliphist)")
    icon: "" // tabler clipboard
    trigger: "clip"
    order: 15
    content: Component {
        ClipboardModule {}
    }
}
