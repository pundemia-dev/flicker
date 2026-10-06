import QtQuick
import "../../api"

LauncherManifest {
    pluginId: "clipboard"
    title: "Буфер обмена"
    description: "История буфера обмена (cliphist)"
    icon: "" // tabler clipboard
    trigger: "clip"
    order: 15
    content: Component {
        ClipboardModule {}
    }
}
