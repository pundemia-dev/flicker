import QtQuick
import Quickshell
import Quickshell.Wayland

// Brings an app to the front or starts it — WM-agnostic: windows are found
// and focused through wlr-foreign-toplevel-management (`ToplevelManager`,
// served by both niri and driftwm), apps launched from their .desktop entry
// (through `launchPrefix`, app2unit like the launcher).
//
// `keys` = names identifying the app (desktop-entry hint, appName, ...);
// they are matched flattened (lower case, alphanumerics only) against the
// toplevel app ids, also as a reverse-domain suffix ("telegramdesktop" ↔
// "orgtelegramdesktop").
Item {
    id: root

    property var launchPrefix: []
    // A sender's default action may map its window only now (Telegram from
    // the tray): focusing is retried a few times, apps can't focus
    // themselves on Wayland.
    property int retryMs: 300
    property int retries: 4

    property var pendingKeys: []
    property int retriesLeft: 0

    function flat(s: var): string {
        return String(s ?? "").toLowerCase().replace(/[^a-z0-9]/g, "");
    }

    function matches(id: string, keys: var): bool {
        const a = root.flat(id);
        if (a.length < 3)
            return false;
        return keys.some(k => k.length >= 3 && (a === k || a.endsWith(k) || k.endsWith(a)));
    }

    // Every name the app may go by: the given ones plus the matching
    // .desktop entry's id / startup class / exec basename.
    function expand(names: var): var {
        const keys = names.map(root.flat).filter(k => k.length >= 3);
        const app = root.desktopEntryFor(keys);
        if (app) {
            keys.push(root.flat(app.id), root.flat(app.startupClass));
            const exec = String(app.command?.[0] ?? "").split("/").pop();
            keys.push(root.flat(exec));
        }
        return [...new Set(keys.filter(k => k.length >= 3))];
    }

    function desktopEntryFor(keys: var): var {
        const apps = DesktopEntries.applications?.values ?? [];
        return apps.find(a => keys.includes(root.flat(a.id)))
            ?? apps.find(a => keys.includes(root.flat(a.name)))
            ?? apps.find(a => root.matches(a.id, keys))
            ?? null;
    }

    function toplevelFor(keys: var): var {
        const all = ToplevelManager.toplevels?.values ?? [];
        // The already focused window first, then any.
        return all.find(t => t.activated && root.matches(t.appId, keys))
            ?? all.find(t => root.matches(t.appId, keys)) ?? null;
    }

    // Focuses an open window of the app; true when one was found.
    function activate(names: var): bool {
        const t = root.toplevelFor(root.expand(names));
        if (!t)
            return false;
        t.activate();
        return true;
    }

    function launch(names: var): bool {
        const app = root.desktopEntryFor(root.expand(names));
        if (!app)
            return false;
        const props = { command: [...(root.launchPrefix ?? []), ...app.command] };
        if (app.workingDirectory)
            props.workingDirectory = app.workingDirectory;
        Quickshell.execDetached(props);
        return true;
    }

    // Focus now, retrying while the window may still be on its way.
    function activateSoon(names: var): void {
        root.pendingKeys = names;
        root.retriesLeft = root.retries;
        retry.restart();
    }

    Timer {
        id: retry
        interval: root.retryMs
        onTriggered: {
            if (root.activate(root.pendingKeys) || --root.retriesLeft <= 0)
                return;
            retry.restart();
        }
    }
}
