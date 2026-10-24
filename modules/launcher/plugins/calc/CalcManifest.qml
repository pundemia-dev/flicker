import QtQuick
import "../../api"
import "../../../../config"

LauncherManifest {
    pluginId: "calc"
    title: I18n.tr("Calculator")
    description: I18n.tr("Math, units, currencies, dates — and the history")
    icon: "\ueb80" // tabler calculator
    trigger: "calc ="
    order: 15
    content: Component {
        CalcModule {}
    }
}
