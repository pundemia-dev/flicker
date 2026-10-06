import QtQuick
import "../../api"
import "../../../../config"

LauncherManifest {
    pluginId: "apps"
    title: I18n.tr("Applications")
    description: I18n.tr("Search and launch applications")
    icon: "" // tabler apps
    trigger: "apps"
    order: 0
    content: Component {
        AppsModule {}
    }
}
