import QtQuick
import "../../../components"
import "../../../config"

// Expanded Night Light card (DropExpand panel): header disc = the toggle
// (against the schedule = until its next turn), the warmth slider (live
// preview while dragging, even when off — services/NightLight.preview),
// today's schedule as a 24 h strip (night amount per 15 min, now marker,
// sunset / sunrise below), the gear opens Settings → Night Light.
Item {
    id: root
    property var services: null
    property var cfg: null
    property var theme: null
    property var frost: null
    property var expander: null
    signal closeRequested

    readonly property var nl: root.services?.nightLight ?? null
    readonly property var pc: root.cfg?.listPanel ?? ({})
    readonly property real pad: root.pc.padding ?? 18
    readonly property color accent: root.theme?.qsOrange ?? "#FF9F0A"
    readonly property color dimColor: root.theme?.cardDim ?? "#99EBEBF5"
    readonly property color plate: root.frost?.layerColor(root.theme?.qsDisc ?? "#3A3A3C") ?? (root.theme?.qsDisc ?? "#3A3A3C")

    // Slider ↔ K in mireds (even steps to the eye): left 6000 K, right 1900 K.
    readonly property real mLo: 1e6 / 6000
    readonly property real mHi: 1e6 / 1900
    function toValue(k: real): real {
        return (1e6 / k - root.mLo) / (root.mHi - root.mLo);
    }
    function toKelvin(v: real): int {
        return Math.round(1e6 / (root.mLo + v * (root.mHi - root.mLo)) / 50) * 50;
    }

    PanelHeader {
        id: header
        width: parent.width
        pc: root.pc
        theme: root.theme
        frost: root.frost
        pad: root.pad
        on: root.nl?.active ?? false
        accent: root.accent
        glyph: on ? "" : ""
        title: I18n.tr("Night Light")
        status: root.nl?.status ?? I18n.tr("Unavailable")
        onToggled: root.nl?.toggle()
        trailing: [
            PanelButton {
                pc: root.pc
                theme: root.theme
                frost: root.frost
                glyph: ""
                onClicked: {
                    root.services?.openSettings?.("nightLight");
                    root.closeRequested();
                }
            }
        ]
    }

    Column {
        y: header.height + 10
        x: root.pad
        width: parent.width - 2 * root.pad
        spacing: 8

        Item {
            width: parent.width
            height: warmthLabel.implicitHeight
            Text {
                id: warmthLabel
                text: I18n.tr("Warmth")
                color: root.dimColor
                font.pixelSize: (root.pc.textSize ?? 14) - 2
            }
            Text {
                anchors.right: parent.right
                text: `${root.nl?.previewK > 0 ? root.nl.previewK : (root.nl?.nightK ?? 3400)} K`
                color: root.dimColor
                font.pixelSize: (root.pc.textSize ?? 14) - 2
                font.features: { "tnum": 1 }
            }
        }
        PanelSlider {
            width: parent.width
            pc: root.pc
            theme: root.theme
            frost: root.frost
            glyph: ""
            mutedGlyph: ""
            fillColor: Qt.tint("#F0F4FB", Qt.alpha(root.accent, 0.55))
            value: root.toValue(root.nl?.nightK ?? 3400)
            onMoved: v => {
                const k = root.toKelvin(v);
                root.nl?.preview(k);
                if (k !== root.nl?.nightK)
                    Config.set("nightLight.temperature", k);
            }
        }

        Item {
            width: parent.width
            height: 6
        }

        // Today, 00:00 → 24:00: night amount per 15 min.
        Item {
            id: strip
            width: parent.width
            height: 22
            readonly property var levels: {
                root.nl?.now;
                return root.nl?.timeline(96) ?? [];
            }
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: root.plate
                clip: true
                Row {
                    anchors.fill: parent
                    Repeater {
                        model: strip.levels.length
                        Rectangle {
                            required property int index
                            width: strip.width / strip.levels.length
                            height: strip.height
                            color: root.accent
                            opacity: strip.levels[index] ?? 0
                        }
                    }
                }
            }
            // Now.
            Rectangle {
                x: Math.round(strip.width * (root.nl?.dayFraction ?? 0)) - 1
                y: -3
                width: 2
                height: strip.height + 6
                radius: 1
                color: "white"
            }
        }
        Item {
            width: parent.width
            height: (root.pc.textSize ?? 14) - 1
            Repeater {
                model: [0, 6, 12, 18, 24]
                Text {
                    required property int modelData
                    x: Math.max(0, Math.min(parent.width - implicitWidth, parent.width * modelData / 24 - implicitWidth / 2))
                    text: String(modelData).padStart(2, "0")
                    color: root.dimColor
                    font.pixelSize: (root.pc.textSize ?? 14) - 4
                    font.features: { "tnum": 1 }
                }
            }
        }

        Item {
            width: parent.width
            height: 4
        }
        // Next sunset / sunrise (custom: the hours), or why there is none.
        Item {
            width: parent.width
            height: (root.pc.textSize ?? 14) + 6
            readonly property string mode: root.nl?.mode ?? "off"
            Row {
                visible: parent.mode !== "off"
                spacing: 6
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ""
                    color: root.accent
                    font.family: root.theme?.iconFamily ?? "tabler-icons"
                    font.pixelSize: root.pc.textSize ?? 14
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (root.nl?.mode === "sun" ? I18n.tr("Sunset %1") : I18n.tr("From %1")).arg(root.nl?.hm(root.nl?.sunset ?? 0) ?? "")
                    color: "white"
                    font.pixelSize: (root.pc.textSize ?? 14) - 1
                }
            }
            Row {
                visible: parent.mode !== "off"
                anchors.right: parent.right
                spacing: 6
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (root.nl?.mode === "sun" ? I18n.tr("Sunrise %1") : I18n.tr("Until %1")).arg(root.nl?.hm(root.nl?.sunrise ?? 0) ?? "")
                    color: "white"
                    font.pixelSize: (root.pc.textSize ?? 14) - 1
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ""
                    color: root.theme?.qsYellow ?? "#FFCC00"
                    font.family: root.theme?.iconFamily ?? "tabler-icons"
                    font.pixelSize: root.pc.textSize ?? 14
                }
            }
            Text {
                visible: parent.mode === "off"
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("No schedule: on and off by hand")
                color: root.dimColor
                font.pixelSize: (root.pc.textSize ?? 14) - 2
            }
        }
    }
}
