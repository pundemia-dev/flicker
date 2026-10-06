import QtQuick
import Quickshell
import "../../fuzzysort.js" as Fuzzy

// Desktop entries + fuzzy search (pShell Apps/Searcher port, fuzzysort
// only): name weighs most, then generic name, keywords-ish comment.
QtObject {
    id: root
    readonly property var apps: DesktopEntries.applications.values
        .filter(a => !a.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name))

    readonly property var prepped: root.apps.map(a => ({
                _app: a,
                name: Fuzzy.prepare(a.name ?? ""),
                generic: Fuzzy.prepare(a.genericName ?? ""),
                comment: Fuzzy.prepare(a.comment ?? "")
            }))

    function query(search: string): var {
        if (!search)
            return root.apps;
        const w = [1, 0.5, 0.2];
        return Fuzzy.go(search, root.prepped, {
            keys: ["name", "generic", "comment"],
            scoreFn: r => {
                let best = 0;
                for (let i = 0; i < w.length; i++)
                    best = Math.max(best, (r[i]?.score ?? 0) * w[i]);
                return best;
            }
        }).map(r => r.obj._app);
    }
}
