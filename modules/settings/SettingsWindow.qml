import QtQuick
import Quickshell
import "../../components"
import "../../config"
import "SettingsSchema.js" as Schema
import "SettingsSearch.js" as Search
import "SettingsVpn.js" as Vpn
import "SettingsAudio.js" as AudioSettings
import "SettingsNotifs.js" as Notifs

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
    required property var audio
    required property var audioDevices
    required property var audioPolicy
    required property var notifications
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
    // WirePlumber's settings are read once per window (Sound section).
    Component.onCompleted: root.audioPolicy?.refreshWp()
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

    // Sound section: the live entry of a device row (AudioSettings.entries).
    function devEntry(ref: var): var {
        return AudioSettings.entries(root.audioDevices, ref.sink).find(e => e.key === ref.key) ?? null;
    }
    function audioValue(row: var): var {
        const e = root.devEntry(row.ref);
        const r = e?.row ?? null;
        const cfg = Config.data.audio ?? {};
        switch (row.key) {
        case "status":
            return AudioSettings.status(e);
        case "name":
            return (cfg.deviceNames ?? {})[row.ref.key] ?? "";
        case "hidden":
            return (cfg.hideDevices ?? []).includes(row.ref.key);
        case "profile":
            return r?.card ? root.audioDevices.profiles(r.card).active : "";
        case "latency":
            return r?.card && r?.port ? root.audioDevices.latencyMs(r.card, r.port) : 0;
        case "balance":
            return (cfg.balance ?? {})[row.ref.key] ?? 0;
        case "variant": {
            const def = row.ref.sink ? root.audioDevices.defaultSink : root.audioDevices.defaultSource;
            const m = (r?.members ?? []).find(x => x.id === def) ?? (r?.members ?? []).find(x => x.id === r.nodeId);
            return m?.name ?? "";
        }
        }
        return undefined;
    }
    function setAudioValue(row: var, value: var): void {
        const r = root.devEntry(row.ref)?.row ?? null;
        const cfg = Config.data.audio ?? {};
        const key = row.ref.key;
        switch (row.key) {
        case "name": {
            const names = Object.assign({}, cfg.deviceNames ?? {});
            if (`${value}`.trim() === "")
                delete names[key];
            else
                names[key] = `${value}`.trim();
            Config.set("audio.deviceNames", names);
            break;
        }
        case "hidden": {
            const list = (cfg.hideDevices ?? []).filter(k => k !== key);
            if (value)
                list.push(key);
            Config.set("audio.hideDevices", list);
            break;
        }
        case "profile":
            if (r?.card)
                root.audioDevices.setProfile(r.card, value);
            break;
        case "latency":
            if (r?.card && r?.port)
                root.audioDevices.setLatency(r.card, r.port, value);
            break;
        case "balance":
            root.audioPolicy.setBalance(key, value);
            break;
        case "variant": {
            const m = (r?.members ?? []).find(x => x.name === value);
            if (m)
                root.audioDevices.makeDefault(m.id, row.ref.sink);
            break;
        }
        }
    }

    function valueOf(row: var): var {
        if (!row.key)
            return undefined;
        if (row.store === "audioDev")
            return root.audioValue(row);
        if (row.store === "wp")
            return root.audioPolicy?.wp?.[row.key];
        if (row.store === "audioPolicy")
            return root.audioPolicy?.[row.key];
        if (row.store === "wallpaper")
            return root.wallpaper?.cfg[row.key];
        if (row.store === "vpn")
            return root.vpn?.[row.key];
        if (row.store === "notifications")
            return root.notifications?.[row.key];
        if (row.store === "notifRule")
            return Notifs.field(root.ruleAt(row.ref), row.key);
        if (row.store === "vpnRule") {
            // A deleted rule's page reads its copy while it slides away.
            const list = root.rules();
            const rule = (row.ref.index < 0 ? row.ref.gone : list[row.ref.index]) ?? {};
            return rule[row.key] ?? { enabled: true, action: "proxy" }[row.key];
        }
        return Config.get(row.key);
    }

    function setValue(row: var, value: var): void {
        if (row.store === "audioDev") {
            root.setAudioValue(row, value);
        } else if (row.store === "wp") {
            root.audioPolicy?.setWp(row.key, value);
        } else if (row.store === "audioPolicy") {
            root.audioPolicy[row.key] = value;
        } else if (row.store === "wallpaper") {
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
        } else if (row.store === "notifications") {
            if (root.notifications)
                root.notifications[row.key] = value;
        } else if (row.store === "notifRule") {
            const list = root.listOf(row.ref).map(r => Object.assign({}, r));
            const rule = list[root.refIndex(row.ref)];
            if (!rule)
                return;
            if (value === Notifs.DEFAULTS[row.key] || row.key === "name" && `${value}`.trim() === "")
                delete rule[row.key];
            else
                rule[row.key] = value;
            Config.set(row.ref.list, list);
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
        if (row.optionsFrom === "audioProfiles") {
            const r = root.devEntry(row.ref)?.row;
            return r?.card ? root.audioDevices.profiles(r.card).options : [];
        }
        if (row.optionsFrom === "audioVariants")
            return (root.devEntry(row.ref)?.row?.members ?? []).map(m => ({ value: m.name, label: m.desc || m.name }));
        return row.options ?? [];
    }

    // A page's groups with the generated ones built (the routing rules,
    // the Sound section's devices / app outputs; "audioDevice" expands to
    // several groups). An unchanged result returns the previous array, so
    // the page keeps its rows (a config write — a balance drag — rebuilt
    // every row under the pointer).
    property var groupsCache: ({})
    function groupsOf(page: var): var {
        const tr = s => I18n.tr(s);
        const hidden = Config.data.audio?.hideDevices ?? [];
        const built = [].concat(...page.groups.map(g => {
            switch (g.generate) {
            case "vpnRules":
                return [Vpn.rulesGroup(g, root.rules(), tr)];
            case "notifRules":
                return [Notifs.rulesGroup(g, Config.get(Notifs.LIST) ?? [], tr)];
            case "audioOutputs":
            case "audioInputs":
                return [AudioSettings.listGroup(g, root.audioDevices, g.generate === "audioOutputs", hidden, tr)];
            case "audioRoutes":
                return [AudioSettings.routesGroup(g, root.audioPolicy, root.audioDevices, tr)];
            case "audioDevice":
                return AudioSettings.deviceGroups(g.ref, root.audioDevices, root.audioPolicy, tr);
            }
            return [g];
        }));
        if (!page.groups.some(g => g.generate))
            return built;
        const id = `${page.title}|${JSON.stringify(page.groups.map(g => g.ref ?? g.generate ?? ""))}`;
        const sig = JSON.stringify(built);
        const hit = root.groupsCache[id];
        if (hit && hit.sig === sig)
            return hit.groups;
        root.groupsCache[id] = { sig: sig, groups: built };
        return built;
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
        case "notifRule": {
            const bad = Notifs.ruleError(root.ruleAt(group.ref), tr);
            if (bad)
                return { text: bad, alert: true };
            break;
        }
        case "notifRuleUntil": {
            const until = root.ruleAt(group.ref)?.until ?? 0;
            if (until > 0)
                return { text: I18n.tr("Expires %1, then the rule is removed.").arg(Notifs.clock(until)), alert: false };
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

    // A rule page's list (ref.list: the VPN routing rules by default) and
    // its rule; a deleted one's page reads its copy while it slides away.
    // A ref with an `id` (notification rules) finds its rule by it: the
    // service reorders that list on its own (mute adds, sweep removes);
    // -1 = deleted / gone.
    function listOf(ref: var): var {
        return Config.get(ref?.list ?? "vpn.routing.rules") ?? [];
    }
    function refIndex(ref: var): int {
        if (!ref || ref.index < 0)
            return -1;
        return ref.id ? root.listOf(ref).findIndex(r => r?.id === ref.id) : ref.index;
    }
    function ruleAt(ref: var): var {
        const i = root.refIndex(ref);
        return (i < 0 ? ref.gone : root.listOf(ref)[i]) ?? {};
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
        case "audioNone":
            return false;
        case "audioUse": {
            const r = root.devEntry(row.ref)?.row;
            return !!r && r.available && !r.isDefault;
        }
        case "audioTestLeft":
        case "audioTestRight":
            return (root.devEntry(row.ref)?.row?.nodeId ?? -1) >= 0;
        case "audioCenter":
            return ((Config.data.audio?.balance ?? {})[row.ref.key] ?? 0) !== 0;
        case "audioUp":
        case "audioDown": {
            const known = row.ref.sink ? root.audioDevices.known.outputs : root.audioDevices.known.inputs;
            const i = known.findIndex(k => k.key === row.ref.key);
            return i >= 0 && (row.action === "audioUp" ? i > 0 : i < known.length - 1);
        }
        case "audioForget":
            return !root.devEntry(row.ref)?.row;
        case "vpnSpeed":
            return !root.vpn?.speedtesting;
        // rules() also makes the binding re-read after a move: the ref's
        // index is a plain JS field, not a notifying property.
        case "ruleUp":
            return root.listOf(row.ref).length > 0 && root.refIndex(row.ref) > 0;
        case "ruleDown": {
            const i = root.refIndex(row.ref);
            return i >= 0 && i < root.listOf(row.ref).length - 1;
        }
        case "notifRuleForever":
            return (root.ruleAt(row.ref).until ?? 0) > 0;
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
        // The rule list the row works on (ref.list; Add rule: the VPN's).
        const path = row.ref?.list ?? "vpn.routing.rules";
        const list = (Config.get(path) ?? []).slice();
        const i = row.ref ? root.refIndex(row.ref) : -1;
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
        case "audioUse": {
            const r = root.devEntry(row.ref)?.row;
            if (r)
                root.audioDevices.choose(r, row.ref.sink);
            break;
        }
        case "audioTestLeft":
        case "audioTestRight":
            root.audioPolicy.testChannel(root.devEntry(row.ref)?.row?.nodeId ?? -1, row.action === "audioTestLeft" ? "left" : "right");
            break;
        case "audioCenter":
            root.audioPolicy.setBalance(row.ref.key, 0);
            break;
        case "audioUp":
        case "audioDown":
            root.audioDevices.moveKnown(row.ref.sink, row.ref.key, row.action === "audioUp" ? -1 : 1);
            break;
        case "audioForget": {
            root.audioDevices.forgetKnown(row.ref.sink, row.ref.key);
            const cfg = Config.data.audio ?? {};
            const names = Object.assign({}, cfg.deviceNames ?? {});
            if (names[row.ref.key] !== undefined) {
                delete names[row.ref.key];
                Config.set("audio.deviceNames", names);
            }
            if ((cfg.hideDevices ?? []).includes(row.ref.key))
                Config.set("audio.hideDevices", cfg.hideDevices.filter(k => k !== row.ref.key));
            stack.pop();
            break;
        }
        case "audioForgetRoute":
            root.audioPolicy.forgetRoutes([row.route]);
            break;
        case "audioForgetRoutes":
            root.audioPolicy.forgetRoutes(["--all"]);
            break;
        case "vpnLogs":
            root.vpn?.openLogs();
            break;
        case "notifRuleAdd": {
            const rules = (Config.get(Notifs.LIST) ?? []).slice();
            const id = root.notifications?.newRuleId() ?? `${Date.now()}`;
            rules.push({ id: id, enabled: true, app: "" });
            Config.set(Notifs.LIST, rules);
            root.push(Notifs.rulePage({ index: rules.length - 1, id: id, list: Notifs.LIST }), row.section ?? "");
            break;
        }
        case "notifRuleForever":
            if (list[i]) {
                list[i] = Object.assign({}, list[i]);
                delete list[i].until;
                Config.set(path, list);
            }
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
            Config.set(path, list);
            break;
        }
        case "ruleDelete":
            // The page keeps a copy while it slides away (and its close
            // does not take the next rule for an empty one).
            // Already gone (expired meanwhile): only the page leaves.
            row.ref.gone = i < 0 ? root.ruleAt(row.ref) : list[i];
            row.ref.index = -1;
            stack.pop();
            if (i < 0)
                break;
            list.splice(i, 1);
            Config.set(path, list);
            break;
        }
    }

    // A page left (popped, or the stack swapped): a rule page whose rule
    // has no matches takes the rule with it (an Add rule left unfilled).
    function pageClosed(page: var): void {
        const ref = page?.ruleRef;
        const at = root.refIndex(ref);
        if (at < 0)
            return;
        const list = root.listOf(ref).slice();
        const empty = ref.list === Notifs.LIST ? Notifs.isEmpty : Vpn.isEmpty;
        if (list[at] && empty(list[at])) {
            list.splice(at, 1);
            ref.index = -1;
            Config.set(ref.list ?? "vpn.routing.rules", list);
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
            const v = key.startsWith("vpn:") ? root.vpn?.[key.slice(4)]
                : key.startsWith("audioPolicy:") ? root.audioPolicy?.[key.slice(12)]
                : key.startsWith("wp:") ? root.audioPolicy?.wp?.[key.slice(3)] : Config.get(key);
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
