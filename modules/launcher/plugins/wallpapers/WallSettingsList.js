.pragma library

// Settings panel rows (WallSettings): key into launcher.wallpapers, tabler
// glyph + tint (a Theme colour name) of the row's icon tile, label and
// value labels as English I18n keys (translated at the display site).
//   bool    — on / off
//   choice  — options [{ value, label, arg? }]: label may hold "%1" = arg
//   reset   — clears every override (back to config.json)
// Pages (tabs, PgUp/PgDn); a page's rows fill a two-column grid in reading
// order (left column first). The first option of every effect parameter is
// "Default" (value "": the flag is left out, wallr's own default applies).
// wallr 0.6 effects: fade, wipe, slide, wave, grow, outer + its aliases
// (simple = linear crossfade, left/right/top/bottom = slide from that edge,
// center = grow from the centre, any = grow from a random point, random =
// a random effect); "island" = grow from the bar (ours).
const EFFECTS = [
    { value: "island", label: "From the island" },
    { value: "fade", label: "Fade" },
    { value: "simple", label: "Crossfade" },
    { value: "wipe", label: "Wipe" },
    { value: "wave", label: "Wave" },
    { value: "slide", label: "Slide" },
    { value: "left", label: "Slide from the left" },
    { value: "right", label: "Slide from the right" },
    { value: "top", label: "Slide from the top" },
    { value: "bottom", label: "Slide from the bottom" },
    { value: "grow", label: "Grow" },
    { value: "center", label: "Grow from the centre" },
    { value: "any", label: "Grow from a random point" },
    { value: "outer", label: "Shrink" },
    { value: "random", label: "Random" }
];

const OPACITY = [
    { value: "", label: "Default" },
    { value: 0, label: "%1", arg: "0" },
    { value: 0.25, label: "%1", arg: "0.25" },
    { value: 0.5, label: "%1", arg: "0.5" },
    { value: 0.75, label: "%1", arg: "0.75" },
    { value: 1, label: "%1", arg: "1" }
];

const PAGES = [
    {
        title: "Transitions",
        glyph: "\uf2b4",
        rows: [
            { key: "effect", glyph: "\uf2b4", tint: "qsBlue", label: "Transition", kind: "choice", options: EFFECTS },
            { key: "durationMs", glyph: "\uea70", tint: "qsOrange", label: "Transition length", kind: "choice", options: [
                    { value: 400, label: "%1 s", arg: "0.4" },
                    { value: 700, label: "%1 s", arg: "0.7" },
                    { value: 1000, label: "%1 s", arg: "1" },
                    { value: 1500, label: "%1 s", arg: "1.5" },
                    { value: 2500, label: "%1 s", arg: "2.5" }
                ] },
            { key: "effectEasing", glyph: "\uef1d", tint: "qsIndigo", label: "Curve", kind: "choice", options: [
                    { value: "", label: "Default" },
                    { value: "bezier", label: "Smooth (bezier)" },
                    { value: "linear", label: "Linear" },
                    { value: "ease_in", label: "Ease in" },
                    { value: "ease_out", label: "Ease out" },
                    { value: "ease_in_out", label: "Ease in and out" }
                ] },
            { key: "effectOrigin", glyph: "\uf02a", tint: "qsGreen", label: "Circle origin", kind: "choice", options: [
                    { value: "", label: "Default" },
                    { value: "center", label: "Centre" },
                    { value: "top_left", label: "Top left" },
                    { value: "top", label: "Top" },
                    { value: "top_right", label: "Top right" },
                    { value: "left", label: "Left" },
                    { value: "right", label: "Right" },
                    { value: "bottom_left", label: "Bottom left" },
                    { value: "bottom", label: "Bottom" },
                    { value: "bottom_right", label: "Bottom right" }
                ] },
            { key: "effectAngle", glyph: "\uef20", tint: "qsOrange", label: "Wipe angle", kind: "choice", options: [
                    { value: "", label: "Default" },
                    { value: 0, label: "%1°", arg: "0" },
                    { value: 45, label: "%1°", arg: "45" },
                    { value: 90, label: "%1°", arg: "90" },
                    { value: 135, label: "%1°", arg: "135" },
                    { value: 180, label: "%1°", arg: "180" },
                    { value: 225, label: "%1°", arg: "225" },
                    { value: 270, label: "%1°", arg: "270" },
                    { value: 315, label: "%1°", arg: "315" }
                ] },
            { key: "effectDirection", glyph: "\uf22f", tint: "qsBlue", label: "Wipe / slide direction", kind: "choice", options: [
                    { value: "", label: "Default" },
                    { value: "1,0", label: "→" },
                    { value: "-1,0", label: "←" },
                    { value: "0,1", label: "↓" },
                    { value: "0,-1", label: "↑" },
                    { value: "1,1", label: "↘" },
                    { value: "-1,1", label: "↙" },
                    { value: "1,-1", label: "↗" },
                    { value: "-1,-1", label: "↖" }
                ] },
            { key: "wipeSoftness", glyph: "\uef8c", tint: "qsIndigo", label: "Wipe edge softness", kind: "choice", options: [
                    { value: "", label: "Default" },
                    { value: 0.002, label: "Razor" },
                    { value: 0.01, label: "Sharp" },
                    { value: 0.05, label: "Soft" },
                    { value: 0.12, label: "Softer" },
                    { value: 0.25, label: "Softest" }
                ] },
            { key: "waveFrequency", glyph: "\uecd4", tint: "qsGreen", label: "Wave frequency", kind: "choice", options: [
                    { value: "", label: "Default" },
                    { value: 1, label: "%1 Hz", arg: "1" },
                    { value: 2, label: "%1 Hz", arg: "2" },
                    { value: 4, label: "%1 Hz", arg: "4" },
                    { value: 8, label: "%1 Hz", arg: "8" },
                    { value: 16, label: "%1 Hz", arg: "16" }
                ] },
            { key: "waveAmplitude", glyph: "\ueb5b", tint: "qsGreen", label: "Wave height", kind: "choice", options: [
                    { value: "", label: "Default" },
                    { value: 0.01, label: "%1", arg: "0.01" },
                    { value: 0.02, label: "%1", arg: "0.02" },
                    { value: 0.05, label: "%1", arg: "0.05" },
                    { value: 0.1, label: "%1", arg: "0.1" },
                    { value: 0.2, label: "%1", arg: "0.2" }
                ] },
            { key: "fadeFrom", glyph: "\uee3f", tint: "accentYellow", label: "Fade start opacity", kind: "choice", options: OPACITY },
            { key: "fadeTo", glyph: "\uec4e", tint: "accentYellow", label: "Fade end opacity", kind: "choice", options: OPACITY },
            { key: "previewEffect", glyph: "\uea9a", tint: "qsBlue", label: "Preview transition", kind: "choice",
                options: [{ value: "same", label: "As when applying" }].concat(EFFECTS) },
            { key: "previewDurationMs", glyph: "\uf549", tint: "qsOrange", label: "Preview length", kind: "choice", options: [
                    { value: 150, label: "%1 s", arg: "0.15" },
                    { value: 300, label: "%1 s", arg: "0.3" },
                    { value: 500, label: "%1 s", arg: "0.5" },
                    { value: 800, label: "%1 s", arg: "0.8" },
                    { value: 1200, label: "%1 s", arg: "1.2" }
                ] },
            { key: "", glyph: "\ufafd", tint: "accentRed", label: "Reset to config", kind: "reset" }
        ]
    },
    {
        title: "General",
        glyph: "\uea03",
        rows: [
            { key: "livePreview", glyph: "\uee88", tint: "qsBlue", label: "Live preview", kind: "bool" },
            { key: "theme", glyph: "\ueb01", tint: "qsIndigo", label: "Colour scheme (wallr)", kind: "choice", options: [
                    { value: "", label: "From wallr config" },
                    { value: "none", label: "Off" },
                    { value: "matugen", label: "matugen" },
                    { value: "wallust", label: "wallust" },
                    { value: "pywal", label: "pywal" }
                ] },
            { key: "accentFromWallpaper", glyph: "\ueb61", tint: "qsOrange", label: "Accent from wallpaper", kind: "bool" },
            { key: "fillBlur", glyph: "\ueb0a", tint: "qsGreen", label: "Blurred fill for odd sizes", kind: "bool" },
            { key: "slideshowIntervalSec", glyph: "\uebc9", tint: "qsBlue", label: "Slideshow interval", kind: "choice", options: [
                    { value: 60, label: "%1 min", arg: "1" },
                    { value: 300, label: "%1 min", arg: "5" },
                    { value: 600, label: "%1 min", arg: "10" },
                    { value: 900, label: "%1 min", arg: "15" },
                    { value: 1800, label: "%1 min", arg: "30" },
                    { value: 3600, label: "%1 h", arg: "1" },
                    { value: 10800, label: "%1 h", arg: "3" }
                ] },
            { key: "slideshowOrder", glyph: "\uf000", tint: "qsIndigo", label: "Slideshow order", kind: "choice", options: [
                    { value: "random", label: "Random" },
                    { value: "sequential", label: "In order" }
                ] },
            { key: "randomFrom", glyph: "\uf08f", tint: "qsOrange", label: "Random picks from", kind: "choice", options: [
                    { value: "all", label: "All" },
                    { value: "favourites", label: "Favourites" }
                ] },
            { key: "pauseOnFullscreen", glyph: "\ued45", tint: "qsGreen", label: "Pause video in fullscreen", kind: "bool" },
            { key: "pauseOnBattery", glyph: "\uea34", tint: "accentYellow", label: "Pause video on battery", kind: "bool" },
            { key: "", glyph: "\ufafd", tint: "accentRed", label: "Reset to config", kind: "reset" }
        ]
    }
];

function optionIndex(row, value) {
    const i = row.options.findIndex(o => o.value === value);
    return i < 0 ? 0 : i;
}

// The next value of a row (dir +1 / -1); null for "reset".
function step(row, value, dir) {
    if (row.kind === "bool")
        return !value;
    if (row.kind === "choice") {
        const n = row.options.length;
        return row.options[(optionIndex(row, value) + dir + n) % n].value;
    }
    return null;
}

// Panel height for a page: segmented control on top, then the page's rows
// (two columns, settingsRowHeight each — rows keep their own height, the
// panel and the island follow the page).
function panelHeight(c, page) {
    const pad = c.settingsPadding ?? 12;
    const top = Math.round(Math.round(pad / 2) + (c.settingsTabHeight ?? 36) + pad);
    const rows = Math.ceil((PAGES[page] ? PAGES[page].rows.length : 0) / 2);
    return top + rows * (c.settingsRowHeight ?? 45) + pad;
}

// Tallest page (the launcher reserves the layer surface for it).
function maxPanelHeight(c) {
    let h = 0;
    for (let i = 0; i < PAGES.length; i++)
        h = Math.max(h, panelHeight(c, i));
    return h;
}
