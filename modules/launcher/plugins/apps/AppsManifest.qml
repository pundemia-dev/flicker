import QtQuick
import "../../api"

LauncherManifest {
    pluginId: "apps"
    title: "Приложения"
    description: "Поиск и запуск приложений"
    icon: "" // tabler apps
    trigger: "apps"
    order: 0
    content: Component {
        AppsModule {}
    }
}
