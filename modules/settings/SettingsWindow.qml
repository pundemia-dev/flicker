import QtQuick
import Quickshell
import "../../components"
import "../../config"
import "SettingsSchema.js" as Schema
import "SettingsSearch.js" as Search

// Settings window: sidebar of sections (iOS tiles; an end-4 style icon rail
// when the window is narrow) + the page in a rounded content card
// (large title, grouped inset lists, drill-down). A search query replaces
// the page with the matching rows — live controls, not links.
// Keys: Ctrl+F search, Esc menu → search → back, Alt+← / mouse back = back,
// Ctrl+PgUp/PgDn = previous / next section.
FloatingWindow {
    id: root
    required property var theme
    required property var wallpaper
    property string initialSection: "general"

    property string section: root.initialSection
    property string query: ""
    readonly property bool searching: root.query.trim() !== ""
    // Rail below this width; the rail expands over the card on demand.
    readonly property bool compact: root.width < 760
    property bool railExpanded: false

    title: I18n.tr("Flicker Settings")
    implicitWidth: 980
    implicitHeight: 680
    minimumSize: Qt.size(440, 380)
    color: root.theme.settingsBg

    function showSection(id: string): void {
        root.query = "";
        root.railExpanded = false;
        if (id === root.section)
            stack.popToRoot();
        root.section = Schema.section(id).id;
    }

    function stepSection(dir: int): void {
        const all = Schema.SECTIONS;
        const i = all.findIndex(s => s.id === root.section);
        root.showSection(all[(i + dir + all.length) % all.length].id);
    }

    // ---- values: the config (or the wallpaper service's overrides) ----

    function valueOf(row: var): var {
        if (row.store === "wallpaper")
            return root.wallpaper?.cfg[row.key];
        return Config.get(row.key);
    }

    function setValue(row: var, value: var): void {
        if (row.store === "wallpaper")
            root.wallpaper?.setSetting(row.key, value);
        else
            Config.set(row.key, value);
    }

    // Drill-down (page rows, multi-select sets).
    function push(page: var): void {
        stack.push(page);
    }

    function back(): bool {
        if (menu.shown) {
            menu.shown = false;
            return true;
        }
        if (root.searching) {
            root.query = "";
            return true;
        }
        if (root.railExpanded) {
            root.railExpanded = false;
            return true;
        }
        return stack.pop();
    }

    function openMenu(row: var, anchor: Item): void {
        menu.open(row, anchor);
    }

    Shortcut { sequences: [StandardKey.Find]; onActivated: sidebar.focusSearch() }
    // A focused text field gets Esc itself (leave / restore).
    readonly property var focusItem: card.Window.activeFocusItem
    readonly property bool editing: root.focusItem?.cursorPosition !== undefined

    Shortcut { sequence: "Escape"; enabled: !root.editing; onActivated: root.back() }
    Shortcut { sequence: "Alt+Left"; onActivated: root.back() }
    Shortcut { sequence: "Ctrl+PgDown"; onActivated: root.stepSection(1) }
    Shortcut { sequence: "Ctrl+PgUp"; onActivated: root.stepSection(-1) }

    // Content card (end-4): inset from the window edge, page stack inside.
    Rectangle {
        id: card
        readonly property real gap: 8
        x: (root.compact ? sidebar.railWidth : sidebar.fullWidth) + gap
        y: gap
        width: root.width - x - gap
        height: root.height - 2 * gap
        radius: 18
        color: root.theme.settingsCard
        clip: true

        SettingsStack {
            id: stack
            anchors.fill: parent
            host: root
            theme: root.theme
            rootPage: Schema.section(root.section)
            visibleWanted: !root.searching
        }

        FadeBlur {
            anchors.fill: parent
            shown: root.searching
            SettingsPage {
                anchors.fill: parent
                host: root
                theme: root.theme
                page: ({
                        title: I18n.tr("Search"),
                        groups: root.searching ? Search.groups(Schema.SECTIONS, root.query, s => I18n.tr(s)) : []
                    })
                emptyText: I18n.tr("No results for “%1”").arg(root.query.trim())
            }
        }

        // Rail expanded over the card: dim it, a click closes the rail.
        Rectangle {
            anchors.fill: parent
            color: root.theme.settingsMenuShade
            opacity: root.compact && root.railExpanded ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
            MouseArea {
                anchors.fill: parent
                onClicked: root.railExpanded = false
            }
        }
    }

    SettingsSidebar {
        id: sidebar
        height: root.height
        host: root
        theme: root.theme
        rail: root.compact && !root.railExpanded
    }

    SettingsMenu {
        id: menu
        anchors.fill: parent
        host: root
        theme: root.theme
    }

    // A press outside the focused text field leaves it (Qt Quick keeps the
    // focus otherwise); the press itself goes on to what is under it.
    MouseArea {
        anchors.fill: parent
        z: 1
        enabled: root.editing
        onPressed: mouse => {
            const f = root.focusItem;
            if (f && !f.contains(f.mapFromItem(this, mouse.x, mouse.y)))
                card.forceActiveFocus();
            mouse.accepted = false;
        }
    }

    // Mouse back / forward buttons: back only (no forward history).
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton
        onClicked: root.back()
    }
}
