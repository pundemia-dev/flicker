import QtQuick
import Quickshell
import "../../api"
import "../../../../components"

// Applications (pShell apps plugin port). Enter launches the selected app
// (through cfg.apps.launchPrefix, app2unit by default — the app gets its
// own systemd scope instead of living under the shell); terminal apps run
// in cfg.apps.terminal. Alt+Enter / the pill button toggles the details
// panel.
LauncherPlugin {
    id: root

    property var selectedApp: null
    property string query: ""
    property var results: []

    // Entry objects cached per DesktopEntry: ScriptModel diffs by identity,
    // so stable objects keep delegates alive across keystrokes.
    property var entryCache: new Map()

    AppsSearch {
        id: search
    }

    ScriptModel {
        id: model
    }
    listModel: model

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged(): void {
            root.entryCache = new Map();
            if (root.isActive)
                root.handleInput(root.query);
        }
    }

    function launch(app: var): void {
        const c = root.cfg?.apps ?? {};
        const cmd = app.runInTerminal ? [...(c.terminal ?? ["kitty"]), ...app.command] : app.command;
        const props = { command: [...(c.launchPrefix ?? []), ...cmd] };
        if (app.workingDirectory)
            props.workingDirectory = app.workingDirectory;
        Quickshell.execDetached(props);
    }

    function entryFor(app: var): var {
        let e = root.entryCache.get(app);
        if (!e) {
            e = {
                header: app.name ?? "",
                text: app.comment || app.genericName || "",
                leftIcon: app.icon ?? "",
                isLeftIconImage: true,
                onClicked: () => {
                    root.launch(app);
                    root.requestClose(true);
                },
                onAltClicked: () => {
                    root.selectedApp = app;
                    root.hasRightPanel = !root.hasRightPanel;
                },
                onSelected: () => root.selectedApp = app
            };
            root.entryCache.set(app, e);
        }
        return e;
    }

    function onActivated(initialQuery: string): void {
        root.hasRightPanel = false;
        handleInput(initialQuery);
    }

    function handleInput(q: string): void {
        root.query = q;
        root.results = search.query(q.trim());
        model.values = root.results.map(a => root.entryFor(a));
        root.selectedApp = root.results[0] ?? null;
    }

    inputExtensionComponent: Component {
        Rectangle {
            radius: height / 2
            color: root.hasRightPanel ? root.theme.qsBlue : (ma.containsMouse ? root.theme.cardTrack : "transparent")

            Text {
                anchors.centerIn: parent
                text: "" // tabler layout-sidebar-right
                font.family: root.theme.iconFamily
                font.pixelSize: root.cfg.iconSize
                color: root.hasRightPanel ? root.theme.islandFg : root.theme.cardDim
            }
            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.hasRightPanel = !root.hasRightPanel
            }
        }
    }

    rightPanelComponent: Component {
        AppsDetailsPanel {
            app: root.selectedApp
            theme: root.theme
            cfg: root.cfg
        }
    }
}
