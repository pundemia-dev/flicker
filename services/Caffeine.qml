import QtQuick
import "../config"

// Caffeine mode: keeps the session awake (no idle dim / lock / suspend).
// The inhibit itself is a Wayland idle-inhibitor that needs a surface:
// every Island holds an `IdleInhibitor` bound to `active` (one visible
// surface is enough; several are harmless). The state survives a restart /
// reboot (statePath("caffeine.json"), restored without an event). Toggling
// posts an event: the cup fills (on) / drains (off) — CoffeeGlyph.
QtObject {
    id: root
    required property var events

    property bool active: false

    function toggle(): void {
        root.setActive(!root.active);
    }
    function setActive(on: bool): void {
        if (on === root.active)
            return;
        root.active = on;
        stateFile.write({ active: on });
        root.events.cancel(on ? "caffeine:off" : "caffeine:on");
        if (!(Config.data.events.caffeine ?? true))
            return;
        root.events.post({
            key: on ? "caffeine:on" : "caffeine:off",
            glyph: "coffee",
            glyphArgs: { drain: !on },
            icon: "", // tabler coffee (font fallback)
            color: "coffee",
            text: on ? I18n.tr("On") : I18n.tr("Off")
        });
    }

    property StateFile stateFile: StateFile {
        name: "caffeine.json"
        onLoaded: {
            if (Config.data.persist?.caffeine ?? true)
                root.active = stateFile.read().active === true;
        }
    }
}
