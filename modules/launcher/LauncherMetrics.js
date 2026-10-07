.pragma library
.import "plugins/wallpapers/CarouselMath.js" as CarouselMath

// Island size of the launcher (StashMetrics pattern): derived from
// config.launcher + the live list so the island fits its content.
// Layout: padding | search row | gap | body (list [| panelGap | hairline |
// panelGap | side panel]) | padding.
// Radius: cfg.radius (see radius()).

// Row height of one list entry: entries with a background image (clipboard
// images) are double height.
function itemHeight(c, entry) {
    return entry && entry.backgroundImage ? c.itemHeight * 2 : c.itemHeight;
}

// Body cap: maxShown regular rows.
function maxListHeight(c) {
    return c.maxShown * c.itemHeight + (c.maxShown - 1) * c.itemSpacing;
}

// Height of the visible list: entries up to the cap, at least one row (the
// empty hint lives there).
function listHeight(c, entries) {
    const list = entries ?? [];
    if (list.length === 0)
        return c.itemHeight;
    let h = 0;
    for (let i = 0; i < list.length; i++) {
        h += itemHeight(c, list[i]) + (i > 0 ? c.itemSpacing : 0);
        if (h >= maxListHeight(c))
            return maxListHeight(c);
    }
    return h;
}

// Top of entry `index` inside the list content (for keeping it in view).
function itemTop(c, entries, index) {
    let y = 0;
    for (let i = 0; i < index && i < entries.length; i++)
        y += itemHeight(c, entries[i]) + c.itemSpacing;
    return y;
}

// cfg.radius (the search row has no plate any more, so nothing to stay
// concentric with); 0 = derive it as padding + inputHeight / 2.
function radius(c) {
    return c.radius > 0 ? c.radius : c.padding + c.inputHeight / 2;
}

// s: { entries, listWidth (-1 = config), panel (bool), panelWidth (-1 = config),
//      body ({ width, height } of a plugin body that replaces the list, or null) }
function islandSize(c, s) {
    if (s.body)
        return {
            width: c.padding * 2 + s.body.width,
            height: c.padding * 2 + c.inputHeight + c.gap + s.body.height,
            radius: radius(c)
        };
    const listW = s.listWidth > 0 ? s.listWidth : c.width;
    const panelW = s.panelWidth > 0 ? s.panelWidth : c.panelWidth;
    // A side panel holds the body at the full cap: a preview must not jump
    // with the result count.
    const body = s.panel ? maxListHeight(c) : listHeight(c, s.entries);
    return {
        // list | panelGap | hairline | panelGap | panel content
        width: c.padding * 2 + listW + (s.panel ? c.panelGap * 2 + c.dividerWidth + panelW : 0),
        height: c.padding * 2 + c.inputHeight + c.gap + body,
        radius: radius(c)
    };
}

// Size to target before the launcher has rendered (ContentSwap handover):
// a plugin opened directly that draws its own body (wallpapers) is known,
// everything else assumes a full list.
function estimate(c, pluginId) {
    if (pluginId === "wallpapers" && c.wallpapers)
        return islandSize(c, { body: { width: CarouselMath.bodyWidth(c.wallpapers), height: c.wallpapers.cardHeight } });
    return { width: c.padding * 2 + c.width, height: maxHeight(c), radius: radius(c) };
}

// Tallest the launcher can get (layer surface reserve while it is open).
// Plugin bodies (the wallpaper carousel) count too.
function maxHeight(c) {
    const body = Math.max(maxListHeight(c), c.wallpapers ? Math.max(c.wallpapers.cardHeight, c.wallpapers.settingsHeight || 0) : 0);
    return c.padding * 2 + c.inputHeight + c.gap + body;
}
