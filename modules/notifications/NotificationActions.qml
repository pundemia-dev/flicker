import QtQuick
import "../../components"
import "../../config"

// Context panel under a notification (flow card + center tiles): Copy
// <code> (one-time codes), the sender's actions, Reply, Mute and Dismiss as
// label-fitted pills centred in the row; stage "mute" = how long (1 hour,
// today, always) instead; stage "reply" = the inline reply field. The owner places it
// below its card, drives `stage` and `reveal` (0..1, follows its own
// growing height) and grows by `panelExtra` while it is open.
Item {
    id: root

    property var entry
    property var cfg
    property var theme
    property var frost: null
    // "" collapsed | "actions" | "mute" | "reply"
    property string stage: ""
    property real reveal: 0

    signal stageRequested(string stage)
    // An action ran / the reply went out: the owner closes or collapses.
    signal finished

    readonly property real buttonH: root.cfg?.flowActionHeight ?? 32
    readonly property real spacing: root.cfg?.flowActionSpacing ?? 8
    readonly property real panelExtra: root.spacing + root.buttonH

    // Owner height above its base: the open panel, or the live pull while
    // dragging (rubber-banded past the panel).
    function extraFor(dragging: bool, pull: real): real {
        const base = root.stage === "" ? 0 : root.panelExtra;
        if (!dragging)
            return base;
        const v = Math.max(0, base + pull);
        return v > root.panelExtra ? root.panelExtra + (v - root.panelExtra) * 0.25 : v;
    }

    // Rim shadow on the pills while they sit on the frosted body.
    readonly property real shadowStrength: root.cfg?.centerInnerShadowStrength ?? 0.06

    function surface(c: color): color {
        return root.frost?.layerColor(c) ?? c;
    }

    readonly property var buttons: {
        const e = root.entry;
        if (!e)
            return [];
        // At most flowMaxActions (Dismiss always stays): kept by priority
        // Dismiss > Copy > Reply > the sender's actions > Mute, shown in
        // the row order Copy, sender's, Reply, Mute, Dismiss.
        const code = { id: "__code", text: I18n.tr("Copy %1").arg(e.code), rank: 1 };
        const reply = { id: "__reply", text: I18n.tr("Reply"), rank: 2 };
        const mute = { id: "__mute", text: I18n.tr("Mute"), rank: 99 };
        const row = [
            ...(e.code ? [code] : []),
            ...(e.actions ?? []).map((a, i) => Object.assign({ rank: 3 + i / 100 }, a)),
            ...(e.canReply ? [reply] : []),
            ...((e.appName ?? "") !== "" ? [mute] : [])
        ];
        const room = Math.max(1, root.cfg?.flowMaxActions ?? 4) - 1;
        const kept = row.slice().sort((a, b) => a.rank - b.rank).slice(0, room);
        return [...row.filter(b => kept.includes(b)), { id: "__dismiss", text: I18n.tr("Dismiss") }];
    }

    readonly property var muteButtons: [
        { id: "__back", text: "\uea60", glyph: true },
        { id: "__hour", text: I18n.tr("1 hour") },
        { id: "__today", text: I18n.tr("Today") },
        { id: "__always", text: I18n.tr("Always") }
    ]

    function press(id: string): void {
        if (id === "__reply" || id === "__mute") {
            root.stageRequested(id.slice(2));
            return;
        }
        if (id === "__back") {
            root.stageRequested("actions");
            return;
        }
        if (id === "__dismiss")
            root.entry?.dismiss();
        else if (id === "__code")
            root.entry?.copyCode();
        else if (id === "__hour" || id === "__today" || id === "__always")
            root.entry?.mute(id.slice(2));
        else
            root.entry?.invoke(id);
        root.finished();
    }

    function send(): void {
        if (root.entry?.reply(input.text)) {
            input.text = "";
            root.finished();
        }
    }

    onStageChanged: {
        if (root.stage === "reply")
            Qt.callLater(() => input.forceActiveFocus());
    }

    height: root.buttonH
    opacity: root.reveal
    visible: opacity > 0.01
    // Slides out from under the card as the owner grows.
    transform: Translate { y: (1 - root.reveal) * -root.buttonH * 0.5 }

    // Label-fitted pills centred in the row (an equal share of the row is
    // only the upper bound); `glyph` = an icon instead of a label.
    component PillRow: Row {
        id: pills
        property var items: []
        anchors.centerIn: parent
        spacing: root.spacing

        Repeater {
            model: pills.items
            delegate: Rectangle {
                id: btn
                required property var modelData
                readonly property real share: (root.width - root.spacing * (pills.items.length - 1)) / Math.max(1, pills.items.length)
                width: Math.min(share, Math.ceil(label.implicitWidth) + 2 * (root.cfg?.flowActionPadding ?? 16))
                height: root.buttonH
                radius: height / 2
                color: root.surface(btnMa.pressed ? (root.theme?.qsDisc ?? "#3A3A3C")
                    : btnMa.containsMouse ? (root.theme?.cardTrack ?? "#2C2C2E") : (root.theme?.cardBg ?? "#1C1C1E"))

                InnerShadow {
                    anchors.fill: parent
                    radius: btn.radius
                    size: Math.round(btn.height * 0.3)
                    strength: root.shadowStrength
                    opacity: root.frost?.progress ?? 0
                }

                Text {
                    id: label
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: btn.modelData.text
                    elide: Text.ElideRight
                    font.family: btn.modelData.glyph ? (root.theme?.iconFamily ?? "tabler-icons") : Qt.application.font.family
                    font.pixelSize: 15
                    color: btn.modelData.id === "__dismiss" || btn.modelData.id === "__back" ? (root.theme?.subtleFg ?? "#B9C0CB") : (root.theme?.islandFg ?? "#E9ECF1")
                }
                MouseArea {
                    id: btnMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.press(btn.modelData.id)
                }
            }
        }
    }

    FadeBlur {
        anchors.fill: parent
        shown: root.stage !== "reply" && root.stage !== "mute"
        PillRow { items: root.buttons }
    }

    FadeBlur {
        anchors.fill: parent
        shown: root.stage === "mute"
        PillRow { items: root.muteButtons }
    }

    FadeBlur {
        anchors.fill: parent
        shown: root.stage === "reply"

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.surface(root.theme?.cardBg ?? "#1C1C1E")

            InnerShadow {
                anchors.fill: parent
                radius: parent.radius
                size: Math.round(parent.height * 0.3)
                strength: root.shadowStrength
                opacity: root.frost?.progress ?? 0
            }

            TextInput {
                id: input
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.right: sendBtn.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                color: root.theme?.islandFg ?? "#E9ECF1"
                selectionColor: root.theme?.qsBlue ?? "#0A84FF"
                font.pixelSize: 15
                enabled: root.stage === "reply"
                Keys.onReturnPressed: root.send()
                Keys.onEnterPressed: root.send()
                Keys.onEscapePressed: root.stageRequested("")

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text.length === 0
                    text: root.entry?.replyPlaceholder || I18n.tr("Reply…")
                    color: root.theme?.subtleFg ?? "#B9C0CB"
                    opacity: 0.6
                    font.pixelSize: 15
                    elide: Text.ElideRight
                    width: parent.width
                }
            }

            Rectangle {
                id: sendBtn
                readonly property bool ready: input.text.trim().length > 0
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: parent.height - 8
                height: width
                radius: width / 2
                color: root.theme?.qsBlue ?? "#0A84FF"
                opacity: ready ? 1 : 0.35
                scale: ready ? 1 : 0.85
                Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
                Behavior on scale { Spring { eps: 0.005 } }

                Text {
                    anchors.centerIn: parent
                    text: ""
                    font.family: root.theme?.iconFamily ?? "tabler-icons"
                    font.pixelSize: 15
                    color: "#FFFFFF"
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: sendBtn.ready
                    onClicked: root.send()
                }
            }
        }
    }
}
