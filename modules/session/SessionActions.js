.pragma library

// Session actions the module knows: tabler glyph, title (English I18n key,
// unused while the module shows no labels) and whether it asks for a
// second press. Order and selection come from Config.session.actions;
// commands from Config.session.commands (services/Session).
const ACTIONS = {
    lock: { glyph: "", title: "Lock", confirm: false },
    logout: { glyph: "", title: "Log Out", confirm: true },
    suspend: { glyph: "", title: "Sleep", confirm: false },
    hibernate: { glyph: "", title: "Hibernate", confirm: true },
    reboot: { glyph: "", title: "Restart", confirm: true },
    poweroff: { glyph: "", title: "Shut Down", confirm: true }
};

function known(ids) {
    return (ids ?? []).filter(id => !!ACTIONS[id]);
}

function of(id) {
    return ACTIONS[id] ?? { glyph: "", title: id, confirm: false };
}

// Island size: one row of glyph buttons; radius from config.
function islandSize(c, count) {
    const n = Math.max(1, count);
    return {
        width: 2 * c.padding + n * c.buttonSize + (n - 1) * c.spacing,
        height: 2 * c.padding + c.buttonSize,
        radius: c.radius
    };
}
