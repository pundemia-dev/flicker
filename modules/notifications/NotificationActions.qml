import QtQuick
import "../../components"
import "../../config"

// Context panel under a notification (flow card + center tiles): the
// sender's actions, Reply and Dismiss as label-fitted pills centred in the
// row, or — stage "reply" — the inline reply field. The owner places it
// below its card, drives `stage` and `reveal` (0..1, follows its own
// growing height) and grows by `panelExtra` while it is open.
Item {
    id: root

    property var entry
    property var cfg
    property var theme
    property var frost: null
    // "" collapsed | "actions" | "reply"
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
        const fixed = [];
        if (e.canReply)
            fixed.push({ id: "__reply", text: I18n.tr("Reply") });
        fixed.push({ id: "__dismiss", text: I18n.tr("Dismiss") });
        const max = root.cfg?.flowMaxActions ?? 4;
        return [...(e.actions ?? []).slice(0, Math.max(0, max - fixed.length)), ...fixed];
    }

    function press(id: string): void {
        if (id === "__reply") {
            root.stageRequested("reply");
            return;
        }
        if (id === "__dismiss")
            root.entry?.dismiss();
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

    FadeBlur {
        anchors.fill: parent
        shown: root.stage !== "reply"

        // Buttons fit their label (+ flowActionPadding), centred; an equal
        // share of the row is only the upper bound.
        Row {
            anchors.centerIn: parent
            spacing: root.spacing

            Repeater {
                model: root.buttons
                delegate: Rectangle {
                    id: btn
                    required property var modelData
                    readonly property real share: (root.width - root.spacing * (root.buttons.length - 1)) / Math.max(1, root.buttons.length)
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
                        font.pixelSize: 15
                        color: btn.modelData.id === "__dismiss" ? (root.theme?.subtleFg ?? "#B9C0CB") : (root.theme?.islandFg ?? "#E9ECF1")
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
