import QtQuick
import "../../api"
import "../../../../config"

LauncherManifest {
    pluginId: "emoji"
    title: I18n.tr("Emoji & symbols")
    description: I18n.tr("Pick one — it is typed into the window")
    icon: "" // tabler mood-smile
    trigger: "emoji symbols smile эмодзи символы смайл"
    order: 18
    content: Component {
        EmojiModule {}
    }
}
