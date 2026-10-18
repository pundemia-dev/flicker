import QtQuick
import "../../components"
import "../../config"

// One row of a group (kinds: SettingsSchema.js; `check` = an option of a
// multi-select page). Optional icon tile, the label, the control on the
// right; a slider row puts its slider on a second line. Rows that open
// something (page, set, menu choice) or toggle (bool, check) take a click
// anywhere and show the pressed cell.
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
    readonly property bool menuChoice: root.kind === "choice" && !root.row.segments
    readonly property bool clickable: ["bool", "check", "page", "set"].includes(root.kind) || root.menuChoice
    readonly property real inset: 16
    readonly property real labelX: root.row.glyph ? root.inset + 29 + 12 : root.inset

    implicitHeight: root.slider ? 84 : 46

    function fmtNumber(v: var): string {
        const n = Number(v ?? 0) / (root.row.scale ?? 1);
        return n.toFixed(root.row.decimals ?? 0) + I18n.tr(root.row.suffix ?? "");
    }

    function optionLabel(v: var): string {
        const o = (root.row.options ?? []).find(o => o.value === v);
        if (!o)
            return v === undefined || v === "" ? I18n.tr("Default") : String(v);
        return o.arg !== undefined ? I18n.tr(o.label).arg(o.arg) : I18n.tr(o.label);
    }

    // Multi-select: is option `v` on (`invert` = the config lists the off ones)?
    function setHas(row: var, list: var, v: var): bool {
        return (list ?? []).includes(v) !== !!row.invert;
    }

    function setSummary(): string {
        const on = root.row.options.filter(o => root.setHas(root.row, root.value, o.value));
        if (on.length === 0)
            return I18n.tr("None");
        if (on.length === root.row.options.length)
            return I18n.tr("All");
        return on.map(o => I18n.tr(o.label)).join(", ");
    }

    function toggleCheck(): void {
        const set = root.row.set;
        const list = root.value ?? [];
        const on = !root.setHas(set, list, root.row.option);
        const known = set.options.map(o => o.value);
        // Canonical option order; values the schema does not know are kept.
        const next = set.options.filter(o => o.value === root.row.option ? on : root.setHas(set, list, o.value))
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
            root.host.push(root.row.page);
        else if (root.kind === "set")
            root.host.push({
                title: root.row.label,
                groups: [{ rows: root.row.options.map(o => ({ kind: "check", label: o.label, option: o.value, set: root.row })) }]
            });
        else if (root.menuChoice)
            root.host.openMenu(root.row, valueText);
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
        enabled: root.clickable
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activate()
    }

    // Top line (the whole row unless it is a slider row).
    Item {
        id: line
        width: parent.width
        height: 46

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
            width: Math.min(implicitWidth, parent.width - x - 120)
            text: I18n.tr(root.row.label)
            elide: Text.ElideRight
            color: root.theme.islandFg
            font.family: root.theme.fontFamily
            font.pixelSize: 15
        }

        // Value / control, right-aligned.
        Row {
            id: control
            anchors.right: parent.right
            anchors.rightMargin: root.kind === "bool" || root.kind === "number" && !root.slider || root.kind === "choice" && root.row.segments ? 12 : root.inset
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Text {
                id: valueText
                visible: root.kind === "number" || root.menuChoice || root.kind === "set"
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, line.width - label.x - label.width - 80)
                elide: Text.ElideRight
                text: root.kind === "number" ? root.fmtNumber(root.value)
                    : root.kind === "set" ? root.setSummary() : root.optionLabel(root.value)
                color: root.theme.settingsSecondary
                font.family: root.theme.fontFamily
                font.pixelSize: 15
            }

            SettingsStepper {
                visible: root.kind === "number" && !root.slider
                anchors.verticalCenter: parent.verticalCenter
                theme: root.theme
                canDown: Number(root.value) > root.row.min
                canUp: Number(root.value) < root.row.max
                onStepped: dir => root.step(dir)
            }

            SettingsSwitch {
                visible: root.kind === "bool"
                anchors.verticalCenter: parent.verticalCenter
                theme: root.theme
                checked: !!root.value
                onToggled: checked => root.host.setValue(root.row, checked)
            }

            SettingsSegments {
                visible: root.kind === "choice" && !!root.row.segments
                anchors.verticalCenter: parent.verticalCenter
                theme: root.theme
                options: root.row.segments ? root.row.options : []
                value: root.value
                onPicked: v => root.host.setValue(root.row, v)
            }

            SettingsField {
                visible: root.kind === "text"
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(80, line.width - label.x - label.width - 40)
                theme: root.theme
                text: root.row.array ? (root.value ?? []).join(" ") : String(root.value ?? "")
                onCommitted: t => root.host.setValue(root.row, root.row.array ? t.split(/\s+/).filter(s => s) : t)
            }

            // Selector / chevron / check mark.
            Text {
                visible: root.menuChoice || root.kind === "page" || root.kind === "set"
                    || root.kind === "check" && root.setHas(root.row.set, root.value, root.row.option)
                anchors.verticalCenter: parent.verticalCenter
                text: root.kind === "check" ? "" : root.menuChoice ? "" : ""
                color: root.kind === "check" ? root.theme.qsBlue : root.theme.settingsSecondary
                opacity: root.kind === "check" ? 1 : 0.7
                font.family: root.theme.iconFamily
                font.pixelSize: root.kind === "check" ? 20 : 17
            }
        }
    }

    SettingsSlider {
        visible: root.slider
        x: root.labelX
        y: line.height - 6
        width: parent.width - x - root.inset
        theme: root.theme
        value: Number(root.value ?? 0)
        min: root.row.min ?? 0
        max: root.row.max ?? 1
        step: root.row.step ?? 0
        onMoved: v => root.host.setValue(root.row, v)
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
