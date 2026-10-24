import QtQuick

// Runtime half of a launcher plugin (pShell LauncherModule contract). The
// manager creates it lazily on first activation and keeps it for the
// launcher session; the host drives it through the functions below.
//
// List entries (`listModel`, a ScriptModel or array) are plain objects read
// by LauncherItem:
//   header, text, rightText        strings
//   leftIcon + isLeftIconImage     tabler glyph, or an icon name (iconPath)
//   swatchColor                    colour plate instead of the icon
//   backgroundImage                url: double-height image row
//   onClicked(), onAltClicked()    Enter / Alt+Enter / click
//   onSelected()                   entry became the current one
Item {
    id: root

    // Injected by the manager on creation.
    property var theme: null
    property var cfg: null
    // Island context (LauncherModule.host): { screen: output name,
    // originX/originY: bar centre on that screen, normalized 0..1,
    // haptics: services/Haptics, wallpaper: services/Wallpaper }.
    property var host: null
    // The launcher's calc/Calculator (shared: rates, history).
    property var calculator: null

    property bool isActive: false

    property var listModel: null
    // Side panel (preview / details) to the right of the list.
    property bool hasRightPanel: false
    property Component rightPanelComponent: null
    // Small control at the right end of the search pill.
    property Component inputExtensionComponent: null
    // Width overrides (-1 = config.launcher.width / panelWidth).
    property real customListWidth: -1
    property real customPanelWidth: -1
    // Custom body INSTEAD of the list + side panel (wallpaper carousel):
    // the island fits bodyWidth x bodyHeight under the search row.
    property Component bodyComponent: null
    property real bodyWidth: 0
    property real bodyHeight: 0

    // Index the host selects after the next model rebuild (-1 = top).
    property int pendingSelection: -1

    // Close the whole launcher (true) or just leave the plugin (false).
    signal requestClose(bool closeLauncher)
    // Put text into the search field (does not run handleInput).
    signal requestSetInput(string text)

    // First chance at a key in the search field (before the list
    // navigation); return true when handled.
    function handleKey(event: var): bool {
        return false;
    }
    // Search text changed (without the magic prefix).
    function handleInput(query: string): void {}
    // Activated: by the picker, as the default plugin, or with a query.
    function onActivated(initialQuery: string): void {}
    function onDeactivated(): void {}
    // First chance at Enter before the current list entry fires; return
    // true when handled.
    function handleExecute(query: string, isAlt: bool): bool {
        return false;
    }
    // Enter with an empty list.
    function execute(query: string, isAlt: bool): void {}
}
