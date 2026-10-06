import QtQuick

// Metadata half of a launcher plugin (pShell LauncherManifest/PluginManifest
// port): cheap to create, the real module (`content`, a LauncherPlugin) is
// built only when the plugin is first activated in a launcher session.
// Each plugin lives in its own folder modules/launcher/plugins/<id>/ and is
// listed once in PluginRegistry.qml.
QtObject {
    // Stable key (`id` is reserved in QML): config.launcher.order /
    // .disabled reference it.
    property string pluginId: ""
    property string title: ""
    // Secondary line in the plugin picker (magic-symbol mode).
    property string description: ""
    // Tabler glyph shown in the picker.
    property string icon: ""
    // Extra word the picker matches on (e.g. "clip").
    property string trigger: ""
    // Default order for plugins not listed in config.launcher.order.
    property int order: 100
    // Builds a LauncherPlugin.
    property Component content: null
}
