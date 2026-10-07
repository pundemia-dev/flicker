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
//   Ctrl+Delete           move the file to the trash
//   Ctrl+F                pictures similar to this one ("~ name")
//   Ctrl+I                settings panel on / off (there: ↑/↓ move,
//                         ←/→ / Enter / Space change, PgUp/PgDn page,
//                         Esc closes it)
// Ctrl combos also match by key position (xkb keycode = evdev + 8): with a
// non-Latin layout active (ru) Ctrl+A arrives as a Cyrillic keysym.
const SCAN = { a: 38, e: 26, d: 40, h: 43, r: 27, s: 39, i: 31, f: 41, bracketLeft: 34, bracketRight: 35 };

function is(e, name, key) {
    return e.key === key || e.nativeScanCode === SCAN[name];
}

// Settings panel: the current page's rows in a column-major two-column
// grid (Up/Down/Tab walk them), Left/Right/Enter/Space change the focused
// row, PgUp/PgDn switch the page, Esc closes the panel.
function settingsKey(p, e) {
    const n = p.settingsRows.length;
    const f = p.settingsFocus;
    switch (e.key) {
    case Qt.Key_Escape:
        p.settingsOpen = false;
        return true;
    case Qt.Key_Up:
    case Qt.Key_Backtab:
        p.settingsFocus = (f - 1 + n) % n;
        return true;
    case Qt.Key_Down:
    case Qt.Key_Tab:
        p.settingsFocus = (f + 1) % n;
        return true;
    case Qt.Key_Left:
        p.changeSetting(f, -1);
        return true;
    case Qt.Key_Right:
    case Qt.Key_Return:
    case Qt.Key_Enter:
    case Qt.Key_Space:
        p.changeSetting(f, 1);
        return true;
    case Qt.Key_PageUp:
        p.setSettingsPage(p.settingsPage - 1);
        return true;
    case Qt.Key_PageDown:
        p.setSettingsPage(p.settingsPage + 1);
        return true;
    }
    return false;
}

function handle(p, e) {
    const shift = (e.modifiers & Qt.ShiftModifier) !== 0;
    const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
    if (ctrl && is(e, "i", Qt.Key_I)) {
        p.settingsOpen = !p.settingsOpen;
        return true;
    }
    if (p.settingsOpen)
        return settingsKey(p, e);
    const page = p.c.pageStep ?? 5;
    const home = () => p.step(-p.selected, true);
    const end = () => p.step(p.entries.length - 1 - p.selected, true);

    if (ctrl) {
        // Toggles never repeat: a chord held a bit long auto-repeated and
        // hid the next card too.
        if (e.isAutoRepeat && shift)
            return true;
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
        if (e.key === Qt.Key_Delete) {
            if (!e.isAutoRepeat)
                p.trashCurrent();
            return true;
        }
        if (is(e, "f", Qt.Key_F)) {
            p.findSimilar();
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
