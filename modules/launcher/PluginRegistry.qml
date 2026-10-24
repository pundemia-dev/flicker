import QtQuick
import "plugins/apps"
import "plugins/clipboard"
import "plugins/wallpapers"
import "plugins/prompter"
import "plugins/calc"

// Launcher plugins (pShell PluginRegistry semantics without folder
// scanning: Quickshell's scanner misses imports of dynamically loaded
// files, so plugins are listed explicitly — one line per plugin folder).
// `active` = not in config.launcher.disabled, ordered by
// config.launcher.order, then the manifest `order` hint, then title;
// active[0] is the default plugin (plain typing).
QtObject {
    id: root
    property var order: []
    property var disabled: []

    readonly property list<QtObject> all: [
        AppsManifest {},
        ClipboardManifest {},
        WallpapersManifest {},
        PrompterManifest {},
        CalcManifest {}
    ]

    readonly property var active: {
        const dis = root.disabled ?? [];
        const ord = root.order ?? [];
        const list = [];
        for (let i = 0; i < root.all.length; i++)
            if (!dis.includes(root.all[i].pluginId))
                list.push(root.all[i]);
        return list.sort((a, b) => {
            const ia = ord.indexOf(a.pluginId), ib = ord.indexOf(b.pluginId);
            if (ia !== -1 || ib !== -1)
                return ia === -1 ? 1 : (ib === -1 ? -1 : ia - ib);
            return a.order - b.order || a.title.localeCompare(b.title);
        });
    }
}
