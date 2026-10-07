.pragma library

// Carousel key map (p = WallpapersModule). Returns true when handled.
//   ←/→ (↑/↓, Tab)        step;  Shift = pageStep cards
//   PgUp/PgDn             pageStep cards
//   Home/End, Ctrl+A/E    first / last card
//   Ctrl+R                random card
//   Ctrl+Shift+A / D      add to / remove from favourites
//   Ctrl+H                hidden files: normal → include → only
//   Ctrl+Shift+H          hide the file (rename to ".name") / unhide it
//   Ctrl+[ / Ctrl+]       back / forward through the wallpaper history
//   Ctrl+S                slideshow over the current view on / off
// Ctrl combos also match by key position (xkb keycode = evdev + 8): with a
// non-Latin layout active (ru) Ctrl+A arrives as a Cyrillic keysym.
const SCAN = { a: 38, e: 26, d: 40, h: 43, r: 27, s: 39, bracketLeft: 34, bracketRight: 35 };

function is(e, name, key) {
    return e.key === key || e.nativeScanCode === SCAN[name];
}

function handle(p, e) {
    const shift = (e.modifiers & Qt.ShiftModifier) !== 0;
    const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
    const page = p.c.pageStep ?? 5;
    const home = () => p.step(-p.selected, true);
    const end = () => p.step(p.entries.length - 1 - p.selected, true);

    if (ctrl) {
        if (is(e, "a", Qt.Key_A)) {
            if (shift)
                p.wallpaper?.setFavourite(p.current?.path ?? "", true);
            else
                home();
            return true;
        }
        if (is(e, "d", Qt.Key_D) && shift) {
            p.wallpaper?.setFavourite(p.current?.path ?? "", false);
            return true;
        }
        if (is(e, "h", Qt.Key_H)) {
            if (shift)
                p.toggleHidden();
            else
                p.cycleVisibility();
            return true;
        }
        if (is(e, "e", Qt.Key_E)) {
            end();
            return true;
        }
        if (is(e, "s", Qt.Key_S)) {
            p.toggleSlideshow();
            return true;
        }
        if (is(e, "r", Qt.Key_R)) {
            p.randomCard();
            return true;
        }
        if (is(e, "bracketLeft", Qt.Key_BracketLeft)) {
            p.historyStep(1);
            return true;
        }
        if (is(e, "bracketRight", Qt.Key_BracketRight)) {
            p.historyStep(-1);
            return true;
        }
    }

    switch (e.key) {
    case Qt.Key_Left:
    case Qt.Key_Up:
    case Qt.Key_Backtab:
        p.step(shift ? -page : -1, e.isAutoRepeat);
        return true;
    case Qt.Key_Right:
    case Qt.Key_Down:
    case Qt.Key_Tab:
        p.step(shift ? page : 1, e.isAutoRepeat);
        return true;
    case Qt.Key_PageUp:
        p.step(-page, true);
        return true;
    case Qt.Key_PageDown:
        p.step(page, true);
        return true;
    case Qt.Key_Home:
        home();
        return true;
    case Qt.Key_End:
        end();
        return true;
    }
    return false;
}
