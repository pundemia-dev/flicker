import QtQuick
import "../../api"
import "../../../../config"

LauncherManifest {
    pluginId: "prompter"
    title: I18n.tr("Teleprompter")
    description: I18n.tr("Markdown scripts that scroll as you speak")
    icon: "" // tabler presentation
    trigger: "prompt"
    order: 30
    content: Component {
        PrompterFilesModule {}
    }
}
