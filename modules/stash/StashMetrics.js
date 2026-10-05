.pragma library

// Island sizes of the stash views (DashMetrics pattern): derived from
// config.stash + live counts so the island fits its content.
// view: "drop" (chooser) | "tray" | "send" (device picker) | "incoming".

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
    return {
        width: pad2 + trayGridWidth(c),
        height: pad2 + rows * c.cellSize + (rows - 1) * c.gap + c.gap + c.actionsHeight
    };
}
