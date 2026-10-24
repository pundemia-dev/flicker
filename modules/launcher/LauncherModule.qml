import QtQuick
import "../../components"
import "LauncherMetrics.js" as Metrics
import "../../config"

// Launcher island (pShell launcher port): search pill on top, the active
// plugin's list below, optional side panel on the right. Plugins live in
// plugins/<id>/ (PluginRegistry); LauncherManager runs the default /
// picker ("!") / active-plugin states. The island size follows the content
// (preferredWidth/Height → ModuleHost → Island, LauncherMetrics).
// payload: { plugin: "<id>", query: "" } opens straight into a plugin.
Item {
    id: root
    required property var payload
    required property var theme
    required property var cfg
    // Island context passed on to plugins (LauncherPlugin.host).
    property var host: null
    signal closeRequested

    readonly property var plugin: manager.currentState === manager.stateSelecting ? null : manager.activePlugin
    // A plugin body (wallpaper carousel) replaces the list + side panel.
    readonly property bool bodyShown: !!root.plugin?.bodyComponent
    readonly property bool panelShown: !root.bodyShown && !!root.plugin?.hasRightPanel && !!root.plugin?.rightPanelComponent
    readonly property real baseListWidth: (root.plugin?.customListWidth ?? -1) > 0 ? root.plugin.customListWidth : root.cfg.width
    // The list gives up launcher.panelListShrink of its width while the side
    // panel is open (TARGET width: the island sizes from it).
    readonly property real listWidth: root.panelShown ? root.baseListWidth * (1 - root.cfg.panelListShrink) : root.baseListWidth
    // Rendered list width: the island's own width spring (Spring {}), so the
    // list narrows in step with the island growing; the hairline and the
    // panel ride on it.
    property real listWidthAnimated: root.listWidth
    Behavior on listWidthAnimated { Spring {} }
    readonly property real panelWidth: (root.plugin?.customPanelWidth ?? -1) > 0 ? root.plugin.customPanelWidth : root.cfg.panelWidth
    readonly property var size: Metrics.islandSize(root.cfg, {
        entries: manager.entries,
        listWidth: root.listWidth,
        panel: root.panelShown,
        panelWidth: root.panelWidth,
        body: root.bodyShown ? { width: root.plugin.bodyWidth, height: root.plugin.bodyHeight } : null
    })
    readonly property real preferredWidth: root.size.width
    readonly property real preferredHeight: root.size.height

    LauncherManager {
        id: manager
        cfg: root.cfg
        theme: root.theme
        host: root.host
    }

    // Also on a re-open over the open launcher (another plugin): the host
    // keeps this instance and only swaps the payload.
    function applyPayload(): void {
        const id = root.payload?.plugin ?? "";
        const q = root.payload?.query ?? "";
        input.setText("");
        if (id) {
            manager.activateById(id, q);
        } else {
            manager.resetToDefault();
            if (q) {
                input.setText(q);
                manager.processInput(q);
            }
        }
    }

    Component.onCompleted: applyPayload()
    onPayloadChanged: applyPayload()

    Connections {
        target: manager.calculator
        function onRequestClose(): void {
            root.closeRequested();
        }
        function onRequestInput(text: string): void {
            input.setText(text);
            manager.processInput(text);
        }
    }

    Connections {
        target: manager.activePlugin
        function onRequestClose(closeLauncher: bool): void {
            if (closeLauncher)
                root.closeRequested();
            else
                input.setText(manager.escapeCurrentState() ?? "");
        }
        function onRequestSetInput(text: string): void {
            input.setText(text);
        }
    }

    function execute(query: string, isAlt: bool): void {
        const entry = list.current;
        if (manager.currentState !== manager.stateSelecting
                && root.plugin?.handleExecute(query, isAlt))
            return;
        if (entry) {
            if (isAlt && typeof entry.onAltClicked === "function")
                entry.onAltClicked();
            else if (typeof entry.onClicked === "function")
                entry.onClicked();
        } else {
            root.plugin?.execute(query, isAlt);
        }
    }

    LauncherInput {
        id: input
        x: root.cfg.padding
        y: root.cfg.padding
        width: root.width - root.cfg.padding * 2
        height: root.cfg.inputHeight
        manager: manager
        theme: root.theme
        cfg: root.cfg
        onMoveUp: list.move(-1)
        onMoveDown: list.move(1)
        onExecute: (query, isAlt) => root.execute(query, isAlt)
        onCloseRequested: root.closeRequested()
    }

    // Thin divider between the search row and the results, centred in the
    // gap and kept short of the island edges.
    Rectangle {
        x: root.cfg.dividerInset
        y: input.y + input.height + (root.cfg.gap - height) / 2
        width: Math.max(0, root.width - root.cfg.dividerInset * 2)
        height: root.cfg.dividerWidth
        radius: height / 2
        color: root.theme.launcherDivider
    }

    LauncherList {
        id: list
        x: root.cfg.padding
        y: input.y + input.height + root.cfg.gap
        width: root.listWidthAnimated
        height: Math.max(0, root.height - y - root.cfg.padding)
        entries: manager.entries
        listKey: manager.listKey
        theme: root.theme
        cfg: root.cfg
        pendingSelection: root.plugin?.pendingSelection ?? -1
        onSelectionApplied: if (root.plugin) root.plugin.pendingSelection = -1
        emptyText: manager.currentState === manager.stateSelecting ? I18n.tr("No such module") : I18n.tr("Nothing found")
        // Gives way to a plugin body (opacity, not visible: see FadeBlur).
        opacity: root.bodyShown ? 0 : 1
        enabled: !root.bodyShown
        Behavior on opacity { Spring { eps: 0.01 } }
    }

    // Plugin body in place of the list (keyed by plugin, so switching
    // plugins rebuilds it).
    FadeBlur {
        id: body
        x: root.cfg.padding
        y: list.y
        width: root.plugin?.bodyWidth ?? 0
        height: root.plugin?.bodyHeight ?? 0
        shown: root.bodyShown

        Loader {
            anchors.fill: parent
            active: body.p > 0.01 && root.bodyShown
            sourceComponent: root.plugin?.bodyComponent ?? null
        }
    }

    // Vertical hairline between the list and the side panel: the same
    // panelGap on both sides (list edge → line → panel content); stops
    // short of the horizontal divider and the island bottom
    // (launcher.panelDividerInset). Fades with the panel.
    Rectangle {
        id: panelDivider
        x: list.x + root.listWidthAnimated + root.cfg.panelGap
        y: list.y + root.cfg.panelDividerInset
        width: root.cfg.dividerWidth
        height: Math.max(0, list.height - root.cfg.panelDividerInset * 2)
        radius: width / 2
        color: root.theme.launcherDivider
        opacity: panel.p
    }

    FadeBlur {
        id: panel
        x: panelDivider.x + panelDivider.width + root.cfg.panelGap
        y: list.y
        width: root.panelWidth
        height: list.height
        shown: root.panelShown

        // No plate (it read as one more, huge, selected row): the content
        // sits on the island body, split from the list by a hairline.
        // Left edge flush: the gap to the hairline is panelGap already.
        Loader {
            anchors.fill: parent
            anchors.margins: root.cfg.itemPadding
            anchors.leftMargin: 0
            active: panel.p > 0.01 && !!root.plugin?.rightPanelComponent
            sourceComponent: root.plugin?.rightPanelComponent ?? null
        }
    }
}
