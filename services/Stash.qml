import QtQuick
import Quickshell
import Quickshell.Io

// File tray (pShell stash port): a scratch directory of dropped files.
// Owns the file model (diff-updated so tile delegates survive refreshes),
// drops (copy | symlink into stashDir), deletes and clear-all. The island
// module (modules/stash) only renders it.
Scope {
    id: root
    required property var cfg

    // $HOME/~-expanded tray dir.
    readonly property string stashDir: root.expand(root.cfg?.stashDir ?? "/tmp/pillshell_stash")
    // Rescan while the tray is on screen (files can change underneath it).
    property bool watching: false
    // A tile is being dragged OUT of the tray (native drag): the island must
    // not take that drag as an incoming drop, nor close the tray under it
    // (that frees the drag's QMimeData mid-drag → segfault in pShell).
    property bool outgoingDrag: false

    readonly property alias model: fileModel
    readonly property int count: fileModel.count

    function expand(p: string): string {
        const home = Quickshell.env("HOME") || "/home/user";
        if (p.startsWith("~"))
            return home + p.slice(1);
        if (p.startsWith("$HOME"))
            return home + p.slice(5);
        return p;
    }

    function shq(s: string): string {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    // file:// URLs (text/uri-list) → absolute local paths.
    function pathsFromUrls(urls: var): var {
        const paths = [];
        for (let i = 0; i < (urls?.length ?? 0); i++) {
            const u = urls[i].toString().trim();
            if (!u.startsWith("file://"))
                continue;
            try {
                paths.push(decodeURIComponent(u.slice(7)));
            } catch (e) {
                console.warn("[Stash] bad drop url:", u);
            }
        }
        return paths;
    }

    // A refresh asked for while a scan runs re-scans once it ends: setting
    // `running` on a running Process is a no-op, so the scan that started
    // before a copy finished would otherwise be the last word.
    property bool rescanQueued: false
    function refresh(): void {
        if (scanner.running)
            root.rescanQueued = true;
        else
            scanner.running = true;
    }
    // The tray shows fresh contents at once, not one watch tick later.
    onWatchingChanged: if (root.watching) root.refresh()

    // Copy (or symlink, cfg.dropMode) each path into the tray dir.
    function drop(paths: var): void {
        if (!paths || paths.length === 0)
            return;
        const dir = root.shq(root.stashDir + "/");
        const op = (root.cfg?.dropMode ?? "copy") === "symlink" ? "ln -sf" : "cp -r --update=none";
        const cmds = paths.map(p => `${op} ${root.shq(p)} ${dir}`);
        root.run(`mkdir -p ${dir} && ${cmds.join("; ")}`);
    }

    function remove(path: string): void {
        root.run(`rm -rf ${root.shq(path)}`);
    }

    function clearAll(): void {
        root.run(`find ${root.shq(root.stashDir)} -mindepth 1 -maxdepth 1 -exec rm -rf {} +`);
    }

    function openFolder(): void {
        Quickshell.execDetached(["xdg-open", root.stashDir]);
    }

    // Favourites float to the front (pShell bookmark), session-only.
    function toggleFav(index: int): void {
        if (index < 0 || index >= fileModel.count)
            return;
        const fav = !fileModel.get(index).isFav;
        fileModel.setProperty(index, "isFav", fav);
        fileModel.move(index, fav ? 0 : fileModel.count - 1, 1);
    }

    function allPaths(): var {
        const out = [];
        for (let i = 0; i < fileModel.count; i++)
            out.push(fileModel.get(i).filePath);
        return out;
    }

    // Shell ops are queued so a drop + delete in quick succession never
    // drops one on the floor (a running Process ignores `running = true`).
    property var pending: []
    function run(cmd: string): void {
        root.pending = root.pending.concat([cmd]);
        if (!worker.running)
            root.next();
    }
    function next(): void {
        if (root.pending.length === 0) {
            root.refresh();
            return;
        }
        worker.command = ["bash", "-c", root.pending[0]];
        root.pending = root.pending.slice(1);
        worker.running = true;
    }

    Process {
        id: worker
        onExited: root.next()
    }

    ListModel {
        id: fileModel
    }

    Process {
        id: scanner
        command: ["bash", "-c", `mkdir -p ${root.shq(root.stashDir)} && ls -1A ${root.shq(root.stashDir)}`]
        onExited: {
            if (root.rescanQueued) {
                root.rescanQueued = false;
                scanner.running = true;
            }
        }
        stdout: StdioCollector {
            id: scanOut
            onStreamFinished: {
                // Diff update: unchanged entries keep their delegates (and
                // thumbnails) instead of being rebuilt on every rescan.
                const names = scanOut.text.split("\n").filter(s => s.length > 0);
                const wanted = new Set(names);
                for (let i = fileModel.count - 1; i >= 0; i--)
                    if (!wanted.has(fileModel.get(i).fileName))
                        fileModel.remove(i);
                const have = new Set();
                for (let i = 0; i < fileModel.count; i++)
                    have.add(fileModel.get(i).fileName);
                for (const n of names) {
                    if (have.has(n))
                        continue;
                    const path = root.stashDir + "/" + n;
                    fileModel.append({
                        fileName: n,
                        filePath: path,
                        fileUrl: "file://" + path.split("/").map(encodeURIComponent).join("/"),
                        isFav: false
                    });
                }
            }
        }
    }

    Timer {
        interval: root.cfg?.watchMs ?? 1500
        repeat: true
        running: root.watching
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()
}
