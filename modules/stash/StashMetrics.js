.pragma library

// Island sizes of the stash views (DashMetrics pattern): derived from
// config.stash + live counts so the island fits its content.
// view: "drop" (chooser) | "tray" | "send" (device picker) | "incoming"
// | "transcript" (fixed cfg size, the text scrolls) | "preview" (Quick
// Look: fitted to the image / video, s.preview = {kind, w, h}).

function trayRows(c, count) {
    return Math.max(1, Math.min(c.rowsMax, Math.ceil(Math.max(1, count) / c.columns)));
}

function trayGridWidth(c) {
    return c.columns * c.cellSize + (c.columns - 1) * c.gap;
}

function islandSize(c, view, s) {
    const pad2 = c.padding * 2;
    if (view === "drop") {
        const zones = c.localsend ? 2 : 1;
        return { width: pad2 + zones * c.dropZoneWidth + (zones - 1) * c.gap, height: pad2 + c.dropZoneHeight };
    }
    if (view === "send") {
        const rows = s.sending ? 1 : Math.max(1, Math.min(c.visibleDevicesMax, s.devices));
        return {
            width: c.pickerWidth,
            height: pad2 + c.pickerHeaderHeight + c.gap + rows * c.deviceRowHeight + (rows - 1) * 4
        };
    }
    if (view === "preview")
        return previewSize(c, s.preview ?? {});
    if (view === "transcript")
        return { width: c.transcriptWidth, height: c.transcriptHeight };
    if (view === "incoming") {
        const body = s.incomingText ? c.incomingTextHeight
            : Math.max(1, Math.min(c.visibleDevicesMax, s.incomingFiles)) * c.incomingFileRowHeight;
        // header + body + (progress | destination) + buttons
        return {
            width: c.incomingWidth,
            height: pad2 + c.pickerHeaderHeight + body + c.actionsHeight * 2 + c.gap * 3
        };
    }
    const rows = trayRows(c, s.files);
    const grid = pad2 + rows * c.cellSize + (rows - 1) * c.gap + c.gap + c.actionsHeight;
    return {
        width: pad2 + trayGridWidth(c),
        // Empty: icon + captions lifted above the island's middle (StashTray).
        height: s.files === 0 ? Math.max(grid, c.emptyHeight ?? 0) : grid
    };
}

function previewSize(c, p) {
    const pad2 = c.padding * 2;
    const head = c.previewHeaderHeight + c.gap;
    const visual = ["image", "animated", "video", "pdf"].includes(p.kind);
    if (visual && p.w > 0 && p.h > 0) {
        const k = Math.min(1, (c.previewMaxWidth - pad2) / p.w, (c.previewMaxHeight - pad2 - head) / p.h);
        return {
            width: Math.round(Math.max(c.previewMinWidth, pad2 + p.w * k)),
            height: Math.round(pad2 + head + p.h * k)
        };
    }
    if (visual || ["text", "dir", "archive"].includes(p.kind))
        return { width: c.previewTextWidth, height: c.previewTextHeight };
    return { width: c.previewInfoWidth, height: c.previewInfoHeight };
}
