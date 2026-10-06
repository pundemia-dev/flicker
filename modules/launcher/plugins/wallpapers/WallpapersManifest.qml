import QtQuick
import "../../api"
import "../../../../config"

LauncherManifest {
    pluginId: "wallpapers"
    title: I18n.tr("Wallpapers")
    description: I18n.tr("Images, GIFs and videos (wallr)")
    icon: "" // tabler wallpaper
    trigger: "wall"
    order: 20
    content: Component {
        WallpapersModule {}
    }
}
