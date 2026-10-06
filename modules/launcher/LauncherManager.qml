import QtQuick
import "fuzzysort.js" as Fuzzy

// Launcher state machine (pShell ModuleManager port).
//   default   — plain typing goes to the default plugin (registry.active[0])
//   selecting — text starts with the magic symbol: the list shows plugins
//   active    — a plugin was picked: a pill in the search field holds it
// Backspace on an empty field steps back (active needs a double press
// within cfg.escapeMs; the pill turns red in between).
Item {
    id: root
    required property var cfg
    required property var theme
    property var host: null

    readonly property int stateDefault: 0
    readonly property int stateSelecting: 1
    readonly property int stateActive: 2
    property int currentState: stateDefault

    readonly property string magicSymbol: root.cfg?.magicSymbol ?? "!"

    readonly property PluginRegistry registry: PluginRegistry {
        order: root.cfg?.order ?? []
        disabled: root.cfg?.disabled ?? []
    }
    readonly property var manifests: registry.active
    readonly property var defaultManifest: manifests.length > 0 ? manifests[0] : null

    property var activeManifest: null
    property var activePlugin: null
    // Plugin picker entries (LauncherItem format).
    property var selectingEntries: []

    // Plugins built so far in this launcher session (manifest id → plugin).
    property var instances: ({})

    property bool escapePending: false

    signal pluginActivated

    // Entries the list shows right now.
    readonly property var entries: {
        if (root.currentState === root.stateSelecting)
            return root.selectingEntries;
        const m = root.activePlugin?.listModel;
        return m?.values ?? m ?? [];
    }
    // Which list this is: a change swaps the whole list (blur-fade), a
    // change of entries under the same key animates row by row.
    readonly property string listKey: root.currentState === root.stateSelecting
        ? "!picker" : (root.activeManifest?.pluginId ?? "")

    // Picker rows built once per manifest (stable identity: LauncherList
    // diffs rows by object).
    property var pickerCache: ({})

    function processInput(text: string): void {
        cancelEscape();
        if (currentState === stateActive) {
            activePlugin?.handleInput(text);
            return;
        }
        if (text.startsWith(magicSymbol)) {
            if (currentState !== stateSelecting) {
                currentState = stateSelecting;
                setActive(null, "");
            }
            updateSelecting(text.substring(magicSymbol.length).trim());
            return;
        }
        if (currentState !== stateDefault) {
            currentState = stateDefault;
            setActive(defaultManifest, "");
        }
        activePlugin?.handleInput(text);
    }

    function activateManifest(manifest: var, initialQuery: string): void {
        currentState = stateActive;
        setActive(manifest, initialQuery);
        pluginActivated();
    }

    function activateById(id: string, initialQuery: string): void {
        const m = manifests.find(x => x.pluginId === id);
        if (m)
            activateManifest(m, initialQuery ?? "");
        else
            console.warn("[Launcher] unknown plugin", id);
    }

    function resetToDefault(): void {
        currentState = stateDefault;
        setActive(defaultManifest, "");
    }

    // Step back one state; returns the text for the search field, or null.
    function escapeCurrentState(): var {
        if (currentState === stateActive) {
            currentState = stateSelecting;
            setActive(null, "");
            updateSelecting("");
            return magicSymbol;
        }
        if (currentState === stateSelecting) {
            resetToDefault();
            return "";
        }
        return null;
    }

    function handleBackspaceOnEmpty(isAutoRepeat: bool): var {
        if (currentState === stateSelecting)
            return escapeCurrentState();
        if (currentState !== stateActive || isAutoRepeat)
            return null;
        if (escapePending) {
            cancelEscape();
            return escapeCurrentState();
        }
        escapePending = true;
        escapeTimer.restart();
        return null;
    }

    function cancelEscape(): void {
        escapePending = false;
        escapeTimer.stop();
    }

    Timer {
        id: escapeTimer
        interval: root.cfg?.escapeMs ?? 400
        onTriggered: root.escapePending = false
    }

    function instanceFor(manifest: var): var {
        if (!manifest)
            return null;
        let inst = instances[manifest.pluginId];
        if (!inst) {
            inst = manifest.content?.createObject(root, { theme: root.theme, cfg: root.cfg });
            if (!inst) {
                console.warn("[Launcher] plugin", manifest.pluginId, "failed:", manifest.content?.errorString());
                return null;
            }
            instances[manifest.pluginId] = inst;
        }
        return inst;
    }

    function setActive(manifest: var, initialQuery: string): void {
        const inst = instanceFor(manifest);
        if (activePlugin && activePlugin !== inst) {
            activePlugin.isActive = false;
            activePlugin.onDeactivated();
        }
        activeManifest = manifest;
        activePlugin = inst;
        if (inst) {
            inst.host = root.host;
            inst.isActive = true;
            inst.onActivated(initialQuery);
        }
    }

    function updateSelecting(query: string): void {
        let found = manifests;
        if (query) {
            const prepped = manifests.map(m => ({
                        _m: m,
                        title: Fuzzy.prepare(m.title),
                        trigger: Fuzzy.prepare(m.trigger || m.pluginId)
                    }));
            found = Fuzzy.go(query, prepped, { keys: ["title", "trigger"] }).map(r => r.obj._m);
        }
        selectingEntries = found.map(m => {
            if (!pickerCache[m.pluginId])
                pickerCache[m.pluginId] = {
                    header: m.title,
                    text: m.description,
                    leftIcon: m.icon,
                    onClicked: () => root.activateManifest(m, "")
                };
            return pickerCache[m.pluginId];
        });
    }
}
