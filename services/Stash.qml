import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// File tray (pShell stash port): a scratch directory of dropped files.
// Owns the file model (diff-updated so tile delegates survive refreshes),
// drops (copy | symlink into stashDir), deletes and clear-all, the
// multi-selection (session; Ctrl/Shift-click, rubber band) and archives
// (scripts/stash/archive.sh: zip a group, extract next to the archive).
// The island module (modules/stash) only renders it.
Scope {
    id: root
    required property var cfg
    // Bar events (services/Events) for the transcription progress.
    property var events: null

    // $HOME/~-expanded tray dir.
    readonly property string stashDir: root.expand(root.cfg?.stashDir ?? "/tmp/pillshell_stash")
    // Rescan while the tray is on screen (files can change underneath it).
    property bool watching: false
    // A tile is being dragged OUT of the tray (native drag): the island must
    // not take that drag as an incoming drop, nor close the tray under it
    // (that frees the drag's QMimeData mid-drag → segfault in pShell).
    property bool outgoingDrag: false

    // Speech-to-text of tray audio / video (WhisperX, one file at a time).
    readonly property alias transcribe: transcribeService

    readonly property alias model: fileModel
    readonly property int count: fileModel.count

    // ── Selection: { <path>: true } (pruned on every rescan) ──
    property var selection: ({})
    readonly property int selectedCount: Object.keys(root.selection).length
    // Shift-click ranges start here (the last plainly toggled tile).
    property string anchorPath: ""

    function isSelected(path: string): bool {
        return root.selection[path] === true;
    }
    function setSelection(paths: var): void {
        const m = {};
        for (const p of paths)
            m[p] = true;
        root.selection = m;
    }
    function toggleSelect(path: string): void {
        const m = Object.assign({}, root.selection);
        if (m[path])
            delete m[path];
        else
            m[path] = true;
        root.selection = m;
        root.anchorPath = path;
    }
    // Anchor → path in tray order, added to the selection.
    function selectRange(path: string): void {
        const all = root.allPaths();
        const a = all.indexOf(root.anchorPath);
        const b = all.indexOf(path);
        if (a < 0 || b < 0) {
            root.toggleSelect(path);
            return;
        }
        const m = Object.assign({}, root.selection);
        for (let i = Math.min(a, b); i <= Math.max(a, b); i++)
            m[all[i]] = true;
        root.selection = m;
    }
    function selectAll(): void {
        root.setSelection(root.allPaths());
    }
    function clearSelection(): void {
        if (root.selectedCount > 0)
            root.selection = {};
    }
    // Selected paths in tray order.
    function selectedPaths(): var {
        return root.allPaths().filter(p => root.selection[p] === true);
    }
    function isDirPath(path: string): bool {
        for (let i = 0; i < fileModel.count; i++)
            if (fileModel.get(i).filePath === path)
                return fileModel.get(i).isDir === true;
        return false;
    }
    function urlOf(path: string): string {
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }
    function removeMany(paths: var): void {
        if (!paths || paths.length === 0)
            return;
        root.run(`rm -rf -- ${paths.map(p => root.shq(p)).join(" ")}`);
    }

    // ── Archives ──
    readonly property string archiveScript: `${Quickshell.shellDir}/scripts/stash/archive.sh`
    // Zip the files into the tray ("<archiveName>.zip", or the file's own
    // stem for a single file; unique names).
    function pack(paths: var): void {
        if (!paths || paths.length === 0)
            return;
        const one = paths.length === 1 ? paths[0].split("/").pop() : "";
        const stem = one !== "" ? (one.includes(".") && !one.startsWith(".") ? one.slice(0, one.lastIndexOf(".")) : one)
            : (root.cfg?.archiveName ?? "Archive");
        root.run(`${root.shq(root.archiveScript)} pack ${root.shq(root.stashDir + "/" + stem + ".zip")} `
            + `${paths.map(p => root.shq(p)).join(" ")} || ${root.failNote("Could not create the archive")}`);
    }
    function unpack(path: string): void {
        root.run(`${root.shq(root.archiveScript)} unpack ${root.shq(path)} ${root.shq(root.stashDir)} `
            + `|| ${root.failNote("Could not extract the archive")}`);
    }
    function failNote(text: string): string {
        return `notify-send -a Stash -i dialog-error ${root.shq(I18n.tr(text))}`;
    }

    // ── Quick Look: what the preview shows ({kind, w, h}, natural px of
    // an image / video, 0 until known) — StashMetrics sizes the island. ──
    property var preview: ({})

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

    Transcribe {
        id: transcribeService
        events: root.events
        // A saved .txt / .srt in the tray shows up at once.
        onWritten: target => {
            if (target.startsWith(root.stashDir + "/"))
                root.refresh();
        }
    }

    ListModel {
        id: fileModel
    }

    Process {
        id: scanner
        command: ["bash", "-c", `mkdir -p ${root.shq(root.stashDir)} && ls -1Ap ${root.shq(root.stashDir)}`]
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
                // `ls -p` marks folders with a trailing "/"; ".unpack.*" =
                // archive.sh temp dirs mid-extract.
                const raw = scanOut.text.split("\n").filter(s => s.length > 0 && !s.startsWith(".unpack."));
                const keyOf = e => e.fileName + (e.isDir ? "/" : "");
                const wanted = new Set(raw);
                for (let i = fileModel.count - 1; i >= 0; i--)
                    if (!wanted.has(keyOf(fileModel.get(i))))
                        fileModel.remove(i);
                const have = new Set();
                for (let i = 0; i < fileModel.count; i++)
                    have.add(keyOf(fileModel.get(i)));
                for (const r of raw) {
                    if (have.has(r))
                        continue;
                    const isDir = r.endsWith("/");
                    const n = isDir ? r.slice(0, -1) : r;
                    const path = root.stashDir + "/" + n;
                    fileModel.append({
                        fileName: n,
                        filePath: path,
                        fileUrl: root.urlOf(path),
                        isDir: isDir,
                        isFav: false
                    });
                }
                // Selection keeps only files that are still there.
                if (root.selectedCount > 0) {
                    const live = root.allPaths().filter(p => root.selection[p] === true);
                    if (live.length !== root.selectedCount)
                        root.setSelection(live);
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
