import QtQuick
import "../../api"
import "../../../../config"

LauncherManifest {
    pluginId: "gifs"
    title: I18n.tr("GIFs")
    description: I18n.tr("Search GIFs (GIPHY / Tenor), Enter copies")
    icon: "邏" // tabler gif
    trigger: "gif gifs giphy tenor"
    order: 35
    content: Component {
        GifsModule {}
    }
}
