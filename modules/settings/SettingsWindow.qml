import QtQuick
import Quickshell
import "../../components"
import "../../config"
import "SettingsSchema.js" as Schema
import "SettingsSearch.js" as Search
import "SettingsVpn.js" as Vpn

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
    required property var vpn
    property string initialSection: "general"

    property string section: Schema.section(root.initialSection).id
    property string query: ""
    readonly property bool searching: root.query.trim() !== ""
    // The results keep the last query while they fade out (cleared, they
    // flashed "No results for “”").
    property string shownQuery: ""
    onQueryChanged: if (root.searching) root.shownQuery = root.query
    // Rail below this width; the rail expands over the card on demand.
    readonly property bool compact: root.width < 760
    property bool railExpanded: false
    onCompactChanged: root.railExpanded = false

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

    // ---- values: the config (or the wallpaper service's overrides, the
    // VPN service's live state, a routing rule's field) ----

    function valueOf(row: var): var {
        if (!row.key)
            return undefined;
        if (row.store === "wallpaper")
            return root.wallpaper?.cfg[row.key];
        if (row.store === "vpn")
            return root.vpn?.[row.key];
        if (row.store === "vpnRule") {
            // A deleted rule's page reads its copy while it slides away.
            const list = root.rules();
            const rule = (row.ref.index < 0 ? row.ref.gone : list[row.ref.index]) ?? {};
            return rule[row.key] ?? { enabled: true, action: "proxy" }[row.key];
        }
        return Config.get(row.key);
    }

    function setValue(row: var, value: var): void {
        if (row.store === "wallpaper") {
            root.wallpaper?.setSetting(row.key, value);
        } else if (row.store === "vpn") {
            if (row.key === "on")
                root.vpn?.setActive(value);
            else if (row.key === "enabled")
                root.vpn?.setAutostart(value);
            else if (row.key === "killswitch")
                root.vpn?.setKillswitch(value);
            else if (row.key === "profile")
                root.vpn?.select(value);
        } else if (row.store === "vpnRule") {
            const list = root.rules().map(r => Object.assign({}, r));
            if (!list[row.ref.index])
                return;
            if (row.key === "name" && value.trim() === "")
                delete list[row.ref.index].name;
            else
                list[row.ref.index][row.key] = value;
            Config.set("vpn.routing.rules", list);
        } else {
            Config.set(row.key, value);
        }
    }

    // Choice options; `optionsFrom` = live ones (the VPN's servers).
    function optionsOf(row: var): var {
        if (row.optionsFrom === "vpnProfiles")
            return (root.vpn?.profiles ?? []).map(p => ({ value: p.tag, label: p.tag }));
        return row.options ?? [];
    }

    // A page's groups with the generated ones built (the routing rules).
    function groupsOf(page: var): var {
        return page.groups.map(g => g.generate === "vpnRules" ? Vpn.rulesGroup(g, root.rules(), s => I18n.tr(s)) : g);
    }

    // ---- live text: labels, details, footers ----

    // Action row label: "…ing" while its operation runs, the confirm text
    // after a first tap.
    function labelOf(row: var): string {
        if (row === root.armed)
            return row.confirm;
        const v = root.vpn;
        switch (row.action) {
        case "vpnApply":
        case "vpnRefresh":
            if (v?.busy === "routing" && root.lastAction === row.action)
                return row.action === "vpnApply" ? "Applying…" : "Downloading…";
            break;
        case "vpnUpdate":
            if (v?.busy === "update")
                return "Updating…";
            break;
        case "vpnPing":
            if (v?.pinging)
                return "Pinging…";
            break;
        case "vpnSpeed":
            if (v?.speedtesting)
                return "Testing…";
            break;
        }
        return row.label;
    }

    // Grey text before the chevron / at the right of an action (translated).
    function detailOf(row: var): string {
        const v = root.vpn;
        if (row.action === "vpnPing")
            return (v?.pingMs ?? -1) === -2 ? I18n.tr("Timeout") : (v?.pingMs ?? -1) >= 0 ? I18n.tr("%1 ms").arg(v.pingMs) : "";
        if (row.action === "vpnSpeed") {
            if (v?.speedError === "missing")
                return I18n.tr("No speedtest-cli");
            if (v?.speedError === "failed")
                return I18n.tr("Failed");
            return v?.speed ? `↓${v.speed.down} ↑${v.speed.up} ${I18n.tr("Mbit/s")}` : "";
        }
        return I18n.tr(row.detail ?? "");
    }

    // A group's footer (translated); `alert` = an error, shown in red.
    // vpnStatus: the last failed operation but routing's; vpnApply: a rule
    // routing.py would reject, else routing's last failure; vpnRule: the
    // rule's first bad matcher.
    function footerOf(group: var): var {
        const plain = { text: I18n.tr(group.footer ?? ""), alert: false };
        const tr = s => I18n.tr(s);
        const err = root.vpn?.error ?? "";
        const failed = err !== "" && err !== "cancelled" && root.vpn?.busy === "" ? err : "";
        switch (group.footerFrom) {
        case "vpnStatus":
            if (failed && root.vpn.errorOp !== "routing")
                return { text: I18n.tr("Last error: %1").arg(failed), alert: true };
            break;
        case "vpnApply": {
            const bad = Vpn.routingError(root.rules(), tr);
            if (bad)
                return { text: bad, alert: true };
            if (failed && root.vpn.errorOp === "routing")
                return { text: I18n.tr("Last error: %1").arg(failed), alert: true };
            break;
        }
        case "vpnRule": {
            const rule = group.ref.index < 0 ? group.ref.gone : root.rules()[group.ref.index];
            const bad = Vpn.ruleError(rule, tr);
            if (bad)
                return { text: bad, alert: true };
            break;
        }
        }
        return plain;
    }

    // ---- action rows ----

    // Action row waiting for its confirming second tap (`confirm`).
    property var armed: null
    Timer {
        id: disarm
        interval: 3000
        onTriggered: root.armed = null
    }
    // Last routing action run (which row says "…ing").
    property string lastAction: ""

    function rules(): var {
        return Config.get("vpn.routing.rules") ?? [];
    }

    function canAct(row: var): bool {
        const idle = !!root.vpn?.installed && root.vpn?.busy === "";
        const valid = () => Vpn.routingError(root.rules(), s => s) === "";
        switch (row.action) {
        case "vpnApply":
            return idle && !!root.vpn?.pending && !!root.vpn?.hasProfiles && valid();
        case "vpnRefresh":
            return idle && !!root.vpn?.hasProfiles && valid();
        case "vpnDiscard":
            return !!root.vpn?.routingPending && root.vpn?.busy !== "routing";
        case "vpnUpdate":
            return idle && !!root.vpn?.subscription;
        case "vpnPing":
            return !root.vpn?.pinging;
        case "vpnSpeed":
            return !root.vpn?.speedtesting;
        // rules() also makes the binding re-read after a move: the ref's
        // index is a plain JS field, not a notifying property.
        case "ruleUp":
            return root.rules().length > 0 && row.ref.index > 0;
        case "ruleDown":
            return row.ref.index < root.rules().length - 1;
        }
        return true;
    }

    function act(row: var): void {
        if (row.confirm && root.armed !== row) {
            root.armed = row;
            disarm.restart();
            return;
        }
        root.armed = null;
        const list = root.rules().slice();
        const i = row.ref?.index ?? -1;
        switch (row.action) {
        case "vpnApply":
        case "vpnRefresh":
            root.lastAction = row.action;
            root.vpn?.applyRouting(row.action === "vpnRefresh");
            break;
        case "vpnDiscard": {
            const a = root.vpn?.appliedRouting ?? {};
            Config.set("vpn.routing", { final: a.final ?? "proxy", rules: JSON.parse(JSON.stringify(a.rules ?? [])) });
            break;
        }
        case "vpnUpdate":
            root.vpn?.updateSubscription();
            break;
        case "vpnPing":
            root.vpn?.testPing();
            break;
        case "vpnSpeed":
            root.vpn?.testSpeed();
            break;
        case "ruleAddTemplate":
            list.push(Object.assign({ enabled: true }, JSON.parse(JSON.stringify(row.rule))));
            Config.set("vpn.routing.rules", list);
            stack.pop();
            break;
        case "vpnEdit":
            root.vpn?.editConfig();
            break;
        case "vpnLogs":
            root.vpn?.openLogs();
            break;
        case "ruleAdd":
            list.push({ action: "direct", match: [], enabled: true });
            Config.set("vpn.routing.rules", list);
            root.push(Vpn.rulePage({ index: list.length - 1 }), row.section ?? "");
            break;
        case "ruleUp":
        case "ruleDown": {
            // The page follows its rule: the ref moves before the config
            // change re-reads the rows.
            const j = i + (row.action === "ruleUp" ? -1 : 1);
            if (i < 0 || j < 0 || j >= list.length)
                break;
            [list[i], list[j]] = [list[j], list[i]];
            row.ref.index = j;
            Config.set("vpn.routing.rules", list);
            break;
        }
        case "ruleDelete":
            // The page keeps a copy while it slides away (and its close
            // does not take the next rule for an empty one).
            row.ref.gone = list[i];
            row.ref.index = -1;
            stack.pop();
            list.splice(i, 1);
            Config.set("vpn.routing.rules", list);
            break;
        }
    }

    // A page left (popped, or the stack swapped): a rule page whose rule
    // has no matches takes the rule with it (an Add rule left unfilled).
    function pageClosed(page: var): void {
        const ref = page?.ruleRef;
        if (!ref || ref.index < 0)
            return;
        const list = root.rules().slice();
        if (list[ref.index] && Vpn.isEmpty(list[ref.index])) {
            list.splice(ref.index, 1);
            ref.index = -1;
            Config.set("vpn.routing.rules", list);
        }
    }

    // A row's dependsOn (SettingsSchema.js): "key", "!key", "key=value",
    // or an array of them (all must hold); "vpn:key" = the VPN service.
    function holds(dep: var): bool {
        if (!dep)
            return true;
        return [].concat(dep).every(d => {
            const neg = d.startsWith("!");
            const [key, want] = d.slice(neg ? 1 : 0).split("=");
            const v = key.startsWith("vpn:") ? root.vpn?.[key.slice(4)] : Config.get(key);
            return (want === undefined ? !!v : String(v) === want) !== neg;
        });
    }

    // Drill-down (page rows, multi-select sets). From the search results
    // (`section` set) the stack was hidden: show the row's section first.
    function push(page: var, sectionId: string): void {
        if (root.searching && sectionId !== "")
            root.showSection(sectionId);
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
        // Follows the sidebar's width spring (stays put while the rail is
        // expanded over it).
        x: (root.railExpanded ? sidebar.railWidth : sidebar.width) + gap
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
                        groups: root.shownQuery.trim() !== "" ? Search.groups(Schema.SECTIONS, root.shownQuery, s => I18n.tr(s)) : []
                    })
                emptyText: I18n.tr("No results for “%1”").arg(root.shownQuery.trim())
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
