import QtQuick
import "../../components"
import "../../config"

// One row of a group (kinds: SettingsSchema.js; `check` = an option of a
// multi-select page). Optional icon tile, the label, the control on the
// right; a slider (and a segmented control too wide for the line) goes on
// a second line. Only the control the kind needs is created (Loader): a
// search keystroke rebuilds every result row. Rows that open something
// (page, set, menu choice) or toggle (bool, check) take a click anywhere
// and show the pressed cell.
Item {
    id: root
    required property var host
    required property var theme
    required property var row
    property bool separator: true
    // Ends of the group card: the pressed cell rounds those corners.
    property bool first: false
    property bool last: false
    property real cardRadius: 12

    readonly property string kind: root.row.kind
    readonly property var value: root.host.valueOf(root.kind === "check" ? root.row.set : root.row)
    readonly property bool slider: root.kind === "number" && !!root.row.slider
    readonly property bool segmented: root.kind === "choice" && !!root.row.segments
    readonly property bool menuChoice: root.kind === "choice" && !root.row.segments
    readonly property bool clickable: ["bool", "check", "page", "set", "action"].includes(root.kind) || root.menuChoice
    readonly property bool checked: root.kind === "check" && root.setHas(root.row.set, root.value, root.row.option)
    // dependsOn not met: the row dims (not its hairline) and takes no input.
    readonly property bool live: root.host.holds(root.row.dependsOn) && (root.kind !== "action" || root.host.canAct(root.row))
    property real liveP: root.live ? 1 : 0.38
    Behavior on liveP { Spring { stiffness: 6; damp: 0.7; eps: 0.005 } }
    readonly property real inset: 16
    readonly property real gap: 10
    readonly property real labelX: root.row.glyph ? root.inset + 29 + 12 : root.inset
    // Controls with their own rim sit closer to the edge than text.
    readonly property real trail: root.kind === "bool" || root.kind === "number" && !root.slider || root.segmented ? 12 : root.inset

    // Second line: the slider, a wide text field, or segments that leave
    // the label no room.
    readonly property bool below: root.slider || root.kind === "text" && !!root.row.wide
        || root.segmented && !!control.item && control.item.width > line.width - root.labelX - root.trail - Math.min(label.implicitWidth, 120) - 12
    readonly property bool inlineControl: !!control.item && !root.below
    // Fixed width right of the label (control, chevron); the label, then
    // the value text / text field share what is left.
    readonly property real fixedWidth: (root.inlineControl && root.kind !== "text" ? control.item.width + root.gap : 0)
        + (chevron.visible ? chevron.implicitWidth + root.gap : 0)
    readonly property real room: line.width - root.labelX - root.trail - root.fixedWidth - 12
    // Grey text of a page / action row (SettingsWindow.detailOf: live for
    // the VPN checks).
    readonly property string detail: root.kind === "page" || root.kind === "action" ? root.host.detailOf(root.row) : ""
    readonly property bool hasValue: root.kind === "number" || root.menuChoice || root.kind === "set" || root.kind === "info"
        || root.detail !== ""

    implicitHeight: !root.below ? 46 : root.kind === "text" ? 76 : 84

    function fmtNumber(v: var): string {
        const n = Number(v ?? 0) / (root.row.scale ?? 1);
        if (root.row.time)
            return `${String(Math.floor(n / 60) % 24).padStart(2, "0")}:${String(Math.round(n) % 60).padStart(2, "0")}`;
        if (n === 0 && root.row.zeroLabel)
            return I18n.tr(root.row.zeroLabel);
        return n.toFixed(root.row.decimals ?? 0) + I18n.tr(root.row.suffix ?? "");
    }

    function optionLabel(v: var): string {
        const o = root.host.optionsOf(root.row).find(o => o.value === v);
        if (!o)
            return v === undefined || v === "" ? I18n.tr("Default") : String(v);
        return o.arg !== undefined ? I18n.tr(o.label).arg(o.arg) : I18n.tr(o.label);
    }

    // Multi-select: is option `v` on (`invert` = the config lists the off ones)?
    function setHas(row: var, list: var, v: var): bool {
        return (list ?? []).includes(v) !== !!row.invert;
    }

    // A set's options (`optionsFrom` = live ones, SettingsWindow.optionsOf).
    readonly property var setOptions: root.kind === "set" ? root.host.optionsOf(root.row) : []

    function setSummary(): string {
        const on = root.setOptions.filter(o => root.setHas(root.row, root.value, o.value));
        if (on.length === 0)
            return I18n.tr("None");
        if (on.length === root.setOptions.length)
            return I18n.tr("All");
        return on.map(o => I18n.tr(o.label)).join(", ");
    }

    function toggleCheck(): void {
        const set = root.row.set;
        const list = root.value ?? [];
        const on = !root.setHas(set, list, root.row.option);
        const options = root.host.optionsOf(set);
        const known = options.map(o => o.value);
        // Canonical option order; values the schema does not know are kept.
        const next = options.filter(o => o.value === root.row.option ? on : root.setHas(set, list, o.value))
            .map(o => o.value);
        const stored = set.invert ? known.filter(v => !next.includes(v)) : next;
        root.host.setValue(set, stored.concat(list.filter(v => !known.includes(v))));
    }

    function step(dir: int): void {
        const r = root.row;
        const v = Number(root.value ?? r.min);
        const next = Math.max(r.min, Math.min(r.max, r.min + Math.round((v + dir * r.step - r.min) / r.step) * r.step));
        root.host.setValue(r, Number(next.toFixed(6)));
    }

    function activate(): void {
        if (root.kind === "bool")
            root.host.setValue(root.row, !root.value);
        else if (root.kind === "check")
            root.toggleCheck();
        else if (root.kind === "page")
            root.host.push(root.row.page, root.row.section ?? "");
        else if (root.kind === "set")
            // Rows built live (SettingsWindow.groupsOf "setChecks"): an
            // `optionsFrom` set follows its source while the page is open.
            root.host.push({
                title: root.row.label,
                groups: [{ generate: "setChecks", set: root.row, ref: root.row.key, rows: [] }]
            }, root.row.section ?? "");
        else if (root.menuChoice)
            root.host.openMenu(root.row, valueText);
        else if (root.kind === "action")
            root.host.act(root.row);
    }

    Rectangle {
        anchors.fill: parent
        topLeftRadius: root.first ? root.cardRadius : 0
        topRightRadius: root.first ? root.cardRadius : 0
        bottomLeftRadius: root.last ? root.cardRadius : 0
        bottomRightRadius: root.last ? root.cardRadius : 0
        color: root.theme.settingsPressed
        opacity: area.pressed ? 1 : 0
        Behavior on opacity { Spring { stiffness: 8; damp: 0.7; eps: 0.01 } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.clickable && root.live
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activate()
    }

    // Top line (the whole row unless the control sits below).
    Item {
        id: line
        width: parent.width
        height: 46
        opacity: root.liveP

        IconTile {
            visible: !!root.row.glyph
            x: root.inset
            anchors.verticalCenter: parent.verticalCenter
            width: 29
            height: 29
            radius: 29 * root.theme.iconTileRadius
            theme: root.theme
            Text {
                anchors.centerIn: parent
                renderType: Text.CurveRendering
                text: root.row.glyph ?? ""
                color: root.theme[root.row.tint] ?? root.theme.qsBlue
                font.family: root.theme.iconFamily
                font.pixelSize: 18
            }
        }

        Text {
            id: label
            x: root.labelX
            anchors.verticalCenter: parent.verticalCenter
            // A text field keeps at least 80 px, a number all of it, a
            // choice / set summary up to 60 (then it elides).
            width: Math.max(0, Math.min(implicitWidth, root.kind === "text" && !root.below ? root.room - 80
                : root.kind === "number" ? root.room - rolling.implicitWidth
                : root.hasValue ? root.room - Math.min(valueText.implicitWidth, 60) : root.room))
            text: I18n.tr(root.kind === "action" ? root.host.labelOf(root.row) : root.row.label)
            elide: Text.ElideRight
            // Action rows read as buttons (iOS blue / red); muted = an off
            // item in a list (a disabled routing rule).
            color: root.kind === "action" ? (root.row.destructive ? root.theme.accentRed : root.theme.qsBlue)
                : root.row.muted ? root.theme.settingsSecondary : root.theme.islandFg
            font.family: root.theme.fontFamily
            font.pixelSize: 15
        }

        // Selector / chevron / check mark at the right edge.
        Text {
            id: chevron
            visible: root.menuChoice || root.kind === "page" || root.kind === "set" || root.kind === "check"
            x: line.width - root.trail - implicitWidth
            anchors.verticalCenter: parent.verticalCenter
            text: root.kind === "check" ? "" : root.menuChoice ? "" : ""
            color: root.kind === "check" ? root.theme.qsBlue : root.theme.settingsSecondary
            // The check mark pops in / out on a spring.
            opacity: root.kind === "check" ? markP : 0.7
            scale: root.kind === "check" ? 0.4 + 0.6 * markP : 1
            property real markP: root.checked ? 1 : 0
            Behavior on markP { Spring { stiffness: 7; damp: 0.45; eps: 0.005 } }
            font.family: root.theme.iconFamily
            font.pixelSize: root.kind === "check" ? 20 : 17
        }

        // Value text: right-aligned before the inline control / chevron.
        readonly property real valueRight: (root.inlineControl && root.kind !== "text" ? control.x : chevron.visible ? chevron.x : line.width - root.trail)
            - (root.inlineControl || chevron.visible ? root.gap : 0)
        readonly property real valueWidth: Math.max(0, root.room - label.width)

        Text {
            id: valueText
            visible: root.menuChoice || root.kind === "set" || root.kind === "info" || root.detail !== ""
            x: line.valueRight - width
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, line.valueWidth)
            elide: Text.ElideRight
            text: root.kind === "set" ? root.setSummary() : root.detail !== "" ? root.detail
                : root.menuChoice || root.kind === "info" ? root.optionLabel(root.value) : ""
            color: root.theme.settingsSecondary
            font.family: root.theme.fontFamily
            font.pixelSize: 15
        }

        // Numbers roll digit by digit (stepper, slider, config edits).
        RollingText {
            id: rolling
            visible: root.kind === "number"
            x: line.valueRight - width
            anchors.verticalCenter: parent.verticalCenter
            width: implicitWidth
            text: root.kind === "number" ? root.fmtNumber(root.value) : ""
            color: root.theme.settingsSecondary
            family: root.theme.fontFamily
            pixelSize: 15
        }
    }

    // The kind's control: inline before the chevron, or on the second line.
    Loader {
        id: control
        opacity: root.liveP
        enabled: root.live
        x: root.below ? root.labelX : (chevron.visible ? chevron.x - root.gap : line.width - root.trail) - width
        y: root.below ? line.height - (root.slider ? 6 : 2) : (line.height - height) / 2
        sourceComponent: root.kind === "bool" ? switchComp
            : root.kind === "number" ? (root.slider ? sliderComp : stepperComp)
            : root.segmented ? segmentsComp
            : root.kind === "text" ? fieldComp : null
    }

    Component {
        id: switchComp
        SettingsSwitch {
            theme: root.theme
            checked: !!root.value
            onToggled: checked => root.host.setValue(root.row, checked)
        }
    }

    Component {
        id: stepperComp
        SettingsStepper {
            theme: root.theme
            canDown: Number(root.value ?? root.row.min) > root.row.min
            canUp: Number(root.value ?? root.row.min) < root.row.max
            onStepped: dir => root.step(dir)
        }
    }

    Component {
        id: segmentsComp
        SettingsSegments {
            theme: root.theme
            options: root.row.options
            value: root.value
            onPicked: v => root.host.setValue(root.row, v)
        }
    }

    Component {
        id: fieldComp
        SettingsField {
            width: root.below ? root.width - root.labelX - root.inset : Math.max(80, line.valueWidth)
            theme: root.theme
            align: root.below ? TextInput.AlignLeft : TextInput.AlignRight
            placeholder: root.row.placeholder ?? ""
            allowEmpty: !!root.row.allowEmpty
            text: root.row.array ? (root.value ?? []).join(" ") : String(root.value ?? "")
            onCommitted: t => root.host.setValue(root.row, root.row.array ? t.split(/\s+/).filter(s => s) : t)
        }
    }

    Component {
        id: sliderComp
        SettingsSlider {
            width: root.width - root.labelX - root.inset
            theme: root.theme
            value: Number(root.value ?? 0)
            min: root.row.min ?? 0
            max: root.row.max ?? 1
            step: root.row.step ?? 0
            onMoved: v => root.host.setValue(root.row, v)
        }
    }

    // Inset hairline (starts at the label, like iOS).
    Rectangle {
        visible: root.separator
        anchors.bottom: parent.bottom
        x: root.labelX
        width: parent.width - x
        height: 1
        color: root.theme.settingsSeparator
        opacity: 0.6
    }
}
