import QtQuick
import Quickshell
import Quickshell.Io
import "../../api"
import "../../../../config"

// Teleprompter scripts: *.md / *.txt under Config.prompter.dir (newest
// first) + "from clipboard". Enter opens it in the island prompter
// (services/Prompter via LauncherPlugin.host.prompter), which replaces the
// launcher.
LauncherPlugin {
    id: root

    property string query: ""
    property var files: []
    readonly property string dir: {
        const d = (Config.data.prompter?.dir ?? "~/Documents/prompter").trim();
        return d.startsWith("~/") ? `${Quickshell.env("HOME")}/${d.slice(2)}` : d;
    }

    ScriptModel {
        id: model
    }
    listModel: model

    function onActivated(initialQuery: string): void {
        listProc.running = true;
        handleInput(initialQuery ?? "");
    }

    function handleInput(q: string): void {
        root.query = (q ?? "").trim().toLowerCase();
        rebuild();
    }

    property var entryCache: new Map()

    function rebuild(): void {
        const q = root.query;
        const rows = [];
        if (q.length === 0)
            rows.push(root.cached("::clipboard", () => ({
                        leftIcon: "", // tabler clipboard-text
                        header: I18n.tr("From clipboard"),
                        text: I18n.tr("Read the copied text"),
                        onClicked: () => root.host?.prompter?.openClipboard()
                    })));
        for (const f of root.files) {
            if (q.length > 0 && !f.name.toLowerCase().includes(q) && !f.rel.toLowerCase().includes(q))
                continue;
            rows.push(root.cached(f.path + "|" + f.mtime, () => ({
                        leftIcon: "", // tabler file-text
                        header: f.name,
                        text: f.rel,
                        rightText: Qt.formatDateTime(new Date(f.mtime * 1000), "dd.MM HH:mm"),
                        onClicked: () => root.host?.prompter?.openFile(f.path)
                    })));
        }
        model.values = rows;
    }

    function cached(key: string, make: var): var {
        let e = root.entryCache.get(key);
        if (!e) {
            e = make();
            root.entryCache.set(key, e);
        }
        return e;
    }

    function execute(query: string, isAlt: bool): void {}

    Process {
        id: listProc
        command: ["find", "-L", root.dir, "-maxdepth", "4", "-type", "f",
            "(", "-iname", "*.md", "-o", "-iname", "*.markdown", "-o", "-iname", "*.txt", ")",
            "-not", "-path", "*/.*", "-printf", "%T@\t%p\n"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of (text ?? "").split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab < 0)
                        continue;
                    const path = line.slice(tab + 1);
                    const base = path.slice(path.lastIndexOf("/") + 1);
                    const rel = path.startsWith(root.dir + "/") ? path.slice(root.dir.length + 1) : path;
                    out.push({
                        path: path,
                        mtime: parseFloat(line.slice(0, tab)),
                        name: base.replace(/\.(md|markdown|txt)$/i, ""),
                        rel: rel.slice(0, Math.max(0, rel.length - base.length)).replace(/\/$/, "")
                    });
                }
                root.files = out.sort((a, b) => b.mtime - a.mtime);
                root.rebuild();
            }
        }
    }
}
