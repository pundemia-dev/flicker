.pragma library

// Settings panel rows (WallSettings): key into launcher.wallpapers, label
// and value labels are English I18n keys (translated at the display site).
//   bool    — on / off
//   choice  — options [{ value, label, arg? }]: label may hold "%1" = arg
//   reset   — clears every override (back to config.json)
// Order = reading order of the two-column grid (left column first).
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

const ROWS = [
    { key: "effect", label: "Transition", kind: "choice", options: EFFECTS },
    { key: "durationMs", label: "Transition length", kind: "choice", options: [
            { value: 400, label: "%1 s", arg: "0.4" },
            { value: 700, label: "%1 s", arg: "0.7" },
            { value: 1000, label: "%1 s", arg: "1" },
            { value: 1500, label: "%1 s", arg: "1.5" },
            { value: 2500, label: "%1 s", arg: "2.5" }
        ] },
    { key: "livePreview", label: "Live preview", kind: "bool" },
    { key: "previewEffect", label: "Preview transition", kind: "choice",
        options: [{ value: "same", label: "As when applying" }].concat(EFFECTS) },
    { key: "previewDurationMs", label: "Preview length", kind: "choice", options: [
            { value: 150, label: "%1 s", arg: "0.15" },
            { value: 300, label: "%1 s", arg: "0.3" },
            { value: 500, label: "%1 s", arg: "0.5" },
            { value: 800, label: "%1 s", arg: "0.8" },
            { value: 1200, label: "%1 s", arg: "1.2" }
        ] },
    { key: "theme", label: "Colour scheme (wallr)", kind: "choice", options: [
            { value: "", label: "From wallr config" },
            { value: "none", label: "Off" },
            { value: "matugen", label: "matugen" },
            { value: "wallust", label: "wallust" },
            { value: "pywal", label: "pywal" }
        ] },
    { key: "accentFromWallpaper", label: "Accent from wallpaper", kind: "bool" },
    { key: "fillBlur", label: "Blurred fill for odd sizes", kind: "bool" },
    { key: "slideshowIntervalSec", label: "Slideshow interval", kind: "choice", options: [
            { value: 60, label: "%1 min", arg: "1" },
            { value: 300, label: "%1 min", arg: "5" },
            { value: 600, label: "%1 min", arg: "10" },
            { value: 900, label: "%1 min", arg: "15" },
            { value: 1800, label: "%1 min", arg: "30" },
            { value: 3600, label: "%1 h", arg: "1" },
            { value: 10800, label: "%1 h", arg: "3" }
        ] },
    { key: "slideshowOrder", label: "Slideshow order", kind: "choice", options: [
            { value: "random", label: "Random" },
            { value: "sequential", label: "In order" }
        ] },
    { key: "randomFrom", label: "Random picks from", kind: "choice", options: [
            { value: "all", label: "All" },
            { value: "favourites", label: "Favourites" }
        ] },
    { key: "pauseOnFullscreen", label: "Pause video in fullscreen", kind: "bool" },
    { key: "pauseOnBattery", label: "Pause video on battery", kind: "bool" },
    { key: "", label: "Reset to config", kind: "reset" }
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
