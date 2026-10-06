import QtQuick
import "../../components"
import "LauncherMetrics.js" as Metrics

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
    signal closeRequested

    readonly property var plugin: manager.currentState === manager.stateSelecting ? null : manager.activePlugin
    readonly property bool panelShown: !!root.plugin?.hasRightPanel && !!root.plugin?.rightPanelComponent
    readonly property real listWidth: (root.plugin?.customListWidth ?? -1) > 0 ? root.plugin.customListWidth : root.cfg.width
    readonly property real panelWidth: (root.plugin?.customPanelWidth ?? -1) > 0 ? root.plugin.customPanelWidth : root.cfg.panelWidth
    readonly property var size: Metrics.islandSize(root.cfg, {
        entries: manager.entries,
        listWidth: root.listWidth,
        panel: root.panelShown,
        panelWidth: root.panelWidth
    })
    readonly property real preferredWidth: root.size.width
    readonly property real preferredHeight: root.size.height

    LauncherManager {
        id: manager
        cfg: root.cfg
        theme: root.theme
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
        width: root.listWidth
        height: Math.max(0, root.height - y - root.cfg.padding)
        entries: manager.entries
        listKey: manager.listKey
        theme: root.theme
        cfg: root.cfg
        pendingSelection: root.plugin?.pendingSelection ?? -1
        onSelectionApplied: if (root.plugin) root.plugin.pendingSelection = -1
        emptyText: manager.currentState === manager.stateSelecting ? "Нет такого модуля" : "Ничего не найдено"
    }

    FadeBlur {
        id: panel
        anchors.right: parent.right
        anchors.rightMargin: root.cfg.padding
        y: list.y
        width: root.panelWidth
        height: list.height
        shown: root.panelShown

        Rectangle {
            anchors.fill: parent
            radius: root.cfg.itemRadius
            color: root.theme.cardBg
        }

        Loader {
            anchors.fill: parent
            anchors.margins: root.cfg.itemPadding
            active: panel.p > 0.01 && !!root.plugin?.rightPanelComponent
            sourceComponent: root.plugin?.rightPanelComponent ?? null
        }
    }
}
