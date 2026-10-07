.pragma library

// Carousel actions (p = WallpapersModule; p.fileService = its
// WallpaperService, p.previewer = WallPreview, p.wallpaper = the shell-wide
// services/Wallpaper, may be null).

// Wheel / touchpad: one card per `unit` of angle delta (a mouse notch =
// 120; touchpads deliver small deltas that accumulate in p.wheelAcc).
function wheel(p, delta, unit) {
    // Touchpads interleave zero-delta events (the other axis): skip them,
    // they must not count as a direction change.
    if (delta === 0)
        return;
    if (p.wheelAcc !== 0 && Math.sign(delta) !== Math.sign(p.wheelAcc))
        p.wheelAcc = 0; // direction change: no leftover from the last swipe
    p.wheelAcc += delta;
    while (Math.abs(p.wheelAcc) >= unit) {
        // Positive = wheel up / content pulled right = previous card.
        const back = p.wheelAcc > 0;
        p.wheelAcc += back ? -unit : unit;
        p.step(back ? -1 : 1, false);
    }
}

// Enter / click on the centre card: through the service (history), with
// the configured effect; closes the launcher.
function apply(p, entry, allOutputs) {
    p.previewer.applied = true;
    p.previewer.cancel();
    const output = allOutputs ? "" : (p.host?.screen ?? "");
    if (p.wallpaper) {
        p.wallpaper.apply(entry.path, p.wallpaper.applyOpts(output));
    } else {
        p.fileService.set(entry.path, {
            output: output,
            effect: p.c.effect ?? "island",
            durationMs: p.c.durationMs ?? 1000,
            originX: p.host?.originX ?? 0.5,
            originY: p.host?.originY ?? 0.03,
            theme: p.c.theme ?? ""
        });
    }
    p.requestClose(true);
}

// Ctrl+Shift+H: hide the centre file (rename to ".name") or bring a hidden
// one back. The carousel shows the new state at once; in the "normal"
// view a hidden card leaves and the slot stays.
function toggleHidden(p) {
    const e = p.current;
    if (!e || !p.wallpaper)
        return;
    const to = p.wallpaper.setHidden(e.path, !e.hidden);
    if (to === e.path)
        return;
    const r = {};
    r[to] = e.path;
    p.renames = r;
    p.fileService.renameFile(e.path, to);
}

// Ctrl+Delete: the centre file to the trash; the card dissolves and the
// rest close the gap (same path as a hide in the normal view).
function trashCurrent(p) {
    const e = p.current;
    if (!e || !p.wallpaper)
        return;
    p.wallpaper.trash(e.path);
    p.fileService.dropFile(e.path);
}

// Ctrl+[ (dir +1, older) / Ctrl+] (-1, newer): walk the history from the
// centre card, skipping files that are gone.
function historyStep(p, dir) {
    const hist = p.wallpaper?.history ?? [];
    const have = {};
    for (const e of p.fileService.files)
        have[e.path] = true;
    let i = hist.indexOf(p.current?.path ?? "");
    if (i === -1 && dir < 0)
        return;
    for (i += dir; i >= 0 && i < hist.length; i += dir)
        if (have[hist[i]]) {
            p.focusOn(hist[i]);
            return;
        }
}

// Ctrl+R: any other card (a far one snaps, a near one flies).
function randomCard(p) {
    const n = p.entries.length;
    if (n < 2)
        return;
    let i = Math.floor(Math.random() * (n - 1));
    if (i >= p.selected)
        i++;
    p.select(i);
}
